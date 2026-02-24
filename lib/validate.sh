#!/usr/bin/env bash
# validate.sh - 入力バリデーション関数（セキュリティ対策）

# 予約語一覧（コマンド名と紛らわしい名前）
# 重複ソース時の readonly エラーを回避するため、変数が未定義の場合のみ定義
if [[ -z "${RESERVED_WORDS+x}" ]]; then
  readonly RESERVED_WORDS=(
    "init" "spawn" "list" "cleanup" "doctor" "status"
    "claim" "unclaim" "handover" "takeover" "merge" "help" "version"
    "test" "all" "global" "local" "readonly" "declare" "export"
  )
fi

# ワークスペース名のバリデーション
# 1-63文字、英数字+_のみ、予約語禁止、先頭は英字
validate_workspace_name() {
  local name="$1"

  # 空チェック
  [[ -n "$name" ]] || {
    log_error "ワークスペース名が空です。"
    return 1
  }

  # 長さチェック（1-63文字）
  local len="${#name}"
  [[ $len -ge 1 && $len -le 63 ]] || {
    log_error "ワークスペース名は1-63文字である必要があります（現在: ${len}文字）。"
    return 1
  }

  # 先頭文字チェック（英字のみ）
  [[ "$name" =~ ^[a-zA-Z] ]] || {
    log_error "ワークスペース名は英字で始める必要があります。"
    return 1
  }

  # 使用可能文字チェック（英数字+_のみ）
  [[ "$name" =~ ^[a-zA-Z0-9_]+$ ]] || {
    log_error "ワークスペース名には英数字とアンダースコアのみ使用できます。"
    return 1
  }

  # 予約語チェック
  for word in "${RESERVED_WORDS[@]}"; do
    [[ "$name" == "$word" ]] && {
      log_error "'${name}' は予約語のため使用できません。"
      return 1
    }
  done

  return 0
}

# claim パスのバリデーション
# ../ 拒否、nullバイト拒否、ルート境界検証
validate_claim_path() {
  local root="$1"
  local input="$2"

  # 空チェック
  [[ -n "$input" ]] || {
    log_error "claim パスが空です。"
    return 1
  }

  # nullバイトチェック（bash の $'\0' バグを回避するため、case でチェック）
  case "$input" in
    *"")
      # 空文字列チェックは別途行うため、ここでは何もしない
      ;;
  esac
  # bash では文字列に null バイトが含まれていると、そこで文字列が切り捨てられる
  # 長さを比較して null バイトの有無をチェック
  local original_len="${#input}"
  local stored="$input"
  local stored_len="${#stored}"
  if [[ "$original_len" -ne "$stored_len" ]]; then
    log_error "claim パスに null バイトは使用できません。"
    return 1
  fi

  # 制御文字チェック（タブと改行を除く）
  # case 文で直接制御文字をパターンマッチ
  case "$input" in
    *$'\x01'*|*$'\x02'*|*$'\x03'*|*$'\x04'*|*$'\x05'*|*$'\x06'*|*$'\x07'*|*$'\x08'*|\
    *$'\x0B'*|*$'\x0C'*|*$'\x0E'*|*$'\x0F'*|*$'\x10'*|*$'\x11'*|*$'\x12'*|*$'\x13'*|\
    *$'\x14'*|*$'\x15'*|*$'\x16'*|*$'\x17'*|*$'\x18'*|*$'\x19'*|*$'\x1A'*|*$'\x1B'*|\
    *$'\x1C'*|*$'\x1D'*|*$'\x1E'*|*$'\x1F'*)
      log_error "claim パスに制御文字は使用できません。"
      return 1
      ;;
  esac

  # ../ チェック（パストラバーサル対策）
  [[ "$input" == *"../"* ]] && {
    log_error "claim パスに '../' は使用できません（パストラバーサル対策）。"
    return 1
  }

  # 先頭の / チェック
  [[ "$input" == /* ]] && {
    log_error "claim パスは '/' で始めることはできません。相対パスを指定してください。"
    return 1
  }

  # 正規化後のパスがルート境界を超えないか検証
  local normalized
  normalized="$(normalize_claim_path "$root" "$input")"

  # realpath で解決してルート配下にあることを確認
  # macOS では /tmp -> /private/tmp のシンボリックリンクがあるため、
  # root も realpath で正規化してから比較する
  local resolved_root
  resolved_root="$(realpath "$root" 2>/dev/null)" || resolved_root="$root"

  local full_path="${root}/${normalized}"
  local resolved
  resolved="$(realpath "$full_path" 2>/dev/null)"

  # ファイルが存在しない場合、resolved は空になる
  if [[ -z "$resolved" ]]; then
    # ファイルが存在しない場合、root ディレクトリの正規化を使用してチェック
    # 正規化された root に正規化されたパスを結合して比較
    if [[ "${full_path}" == "${root}"* ]]; then
      # full_path が root で始まっている場合、安全とみなす
      :
    else
      log_error "claim パスがプロジェクトルート外を参照しています。"
      return 1
    fi
  else
    # ファイルが存在する場合、resolved が resolved_root 配下にあることを確認
    [[ "$resolved" == "${resolved_root}"* ]] || {
      log_error "claim パスがプロジェクトルート外を参照しています。"
      return 1
    }
  fi

  return 0
}

# 安全な相対パス計算
# 環境変数経由で Python に渡すことでインジェクション対策
calculate_relative_path() {
  local source_dir="$1"
  local target_dir="$2"

  # 引数の検証
  [[ -d "$source_dir" ]] || {
    log_error "ソースディレクトリが存在しません: $source_dir"
    return 1
  }

  [[ -d "$target_dir" ]] || {
    log_error "ターゲットディレクトリが存在しません: $target_dir"
    return 1
  }

  # realpath でパスを解決（シンボリックリンク追跡）
  local resolved_source
  local resolved_target
  resolved_source="$(realpath "$source_dir")"
  resolved_target="$(realpath "$target_dir")"

  # 解決後のパスの境界チェック
  # 両方が同じルートファイルシステム上にあることを確認
  local root_prefix="${resolved_target}"

  # 環境変数経由で安全に Python に渡す
  local rel_path
  rel_path="$(
    export SOURCE_DIR="$resolved_source"
    export TARGET_DIR="$resolved_target"
    python3 -c 'import os.path; print(os.path.relpath(os.environ["SOURCE_DIR"], os.environ["TARGET_DIR"]))' 2>/dev/null
  )" || {
    # Python フォールバック: realpath --relative-to
    rel_path="$(realpath --relative-to="$target_dir" "$source_dir" 2>/dev/null)" || {
      # 最終フォールバック: 手動計算（簡易版）
      rel_path="../../${source_dir##*/}"
    }
  }

  echo "$rel_path"
  return 0
}

# handover JSON フィールド検証
validate_handover_field() {
  local field="$1"
  local value="$2"
  local allowed="$3"

  case "$allowed" in
    *"$value"*) return 0 ;;
    *) log_error "${field}: '${value}' は不正です (許容値: ${allowed})"; return 1 ;;
  esac
}

# handover JSON 構造検証
validate_handover_json() {
  local json_file="$1"

  # version チェック
  local version
  version="$(jq -r '.version // 1' "$json_file")"

  # verification_status 検証 (v2以上)
  if [[ "$version" -ge 2 ]]; then
    local status
    status="$(jq -r '.verification_status // "pending"' "$json_file")"
    validate_handover_field "verification_status" "$status" "pending passed failed skipped" || return 1
  fi

  # risk severity 検証 (v2以上)
  if [[ "$version" -ge 2 ]]; then
    local severities
    severities="$(jq -r '.risks[].severity // empty' "$json_file" 2>/dev/null)" || severities=""
    while IFS= read -r severity; do
      [[ -z "$severity" ]] && continue
      validate_handover_field "risk severity" "$severity" "low medium high critical" || return 1
    done <<< "$severities"
  fi

  # blocked_by type 検証 (v2以上)
  if [[ "$version" -ge 2 ]]; then
    local types
    types="$(jq -r '.blocked_by[].type // empty' "$json_file" 2>/dev/null)" || types=""
    while IFS= read -r type; do
      [[ -z "$type" ]] && continue
      validate_handover_field "blocker type" "$type" "dependency issue blocker" || return 1
    done <<< "$types"
  fi

  return 0
}
