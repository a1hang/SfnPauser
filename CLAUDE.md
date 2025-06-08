# プロジェクト設定

## 言語設定
- 全ての応答は日本語で行うこと
- コメントやドキュメントも日本語で記載すること

## GitHub Flow ワークフロー規約

### 基本原則
このプロジェクトでは GitHub Flow を採用し、全ての変更はプルリクエスト（PR）を通して行う。

### Claude Code での作業手順

#### 1. ブランチ作成とコミット
```bash
# 機能・修正ごとに新しいブランチを作成
git checkout -b feature/branch-name
# または
git checkout -b fix/issue-description

# 変更実装後、適切な単位でコミット
git add .
git commit -m "変更内容の説明

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# ブランチをリモートにプッシュ
git push -u origin feature/branch-name
```

#### 2. プルリクエスト作成
```bash
# GitHub CLI でPR作成
gh pr create --title "変更のタイトル" --body "$(cat <<'EOF'
## 変更内容
- 主な変更点1
- 主な変更点2

## 動作確認
- [ ] 確認項目1
- [ ] 確認項目2

## 関連情報
（必要に応じて追加情報）
EOF
)"
```

#### 3. ブランチ命名規則
- **新機能**: `feature/機能名`
- **バグ修正**: `fix/修正内容`
- **ドキュメント**: `docs/更新内容`
- **リファクタリング**: `refactor/対象`
- **設定変更**: `config/変更内容`

#### 4. コミットメッセージ規則
- 1行目: 変更の概要（50文字以内）
- 2行目: 空行
- 3行目以降: 詳細説明（必要に応じて）
- 末尾: Claude Code の署名を必須で追加

### ユーザーの作業

#### 1. GitHub上でのレビュー
- PRページで変更内容を確認
- 必要に応じてコメント・フィードバック
- 承認 (Approve) または変更依頼 (Request changes)

#### 2. マージ
- 承認後、GitHub UI または CLI でマージ
- マージ後、ローカルでブランチクリーンアップ:
```bash
git checkout main
git pull origin main
git branch -d feature/branch-name
```

### 禁止事項
- mainブランチへの直接コミット・プッシュ
- レビューなしでのマージ
- PRを経由しない変更の反映

### 例外
- 緊急時のホットフィックス（事後にPRで経緯を記録）
- ドキュメントの軽微な誤字修正（可能な限りPRを推奨）

## その他のプロジェクトルール
- Python 3.13 ランタイムを使用
- AWS Lambda のベストプラクティスに従う
- セキュリティ情報（キー、シークレット）をコミットに含めない