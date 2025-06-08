# StepFunctions Pauser (SfnPauser)

AWS Step Functions のメンテナンスモード管理を行う Lambda 関数プロジェクトです。

## 概要

このプロジェクトは、AWS Step Functions のワークフロー実行中にメンテナンスが必要になった際に、タスクを一時停止・保存し、メンテナンス完了後に再開する機能を提供します。

## 主な機能

### メンテナンスモード有効時
- Step Functions からのタスクトークンを S3 に安全に保存
- UUIDを使用したユニークなファイル名で保存
- StepFunctions名別のフォルダ構造で整理

### メンテナンスモード無効時
- 保存されたタスクトークンを使用してワークフローを再開
- S3 から完了したタスクトークンを自動削除
- 新しいタスクは即座に完了応答

## 入力パラメータ

Lambda 関数の event には以下のパラメータが必要です：

| パラメータ名 | 説明 | 必須 | 例 |
|------------|------|------|-----|
| `taskToken` | StepFunctions タスクトークン | ✓ | `"AQC..."` |
| `stateMachineArn` | StepFunctions ステートマシン ARN | ✓ | `"arn:aws:states:..."` |

## 環境変数

Lambda 関数で以下の環境変数を設定してください：

| 変数名 | 説明 | 必須 | デフォルト値 |
|--------|------|------|--------------|
| `Bucket` | タスクトークンを保存する S3 バケット名 | ✓ | - |
| `Prefix` | S3 オブジェクトキーのプリフィックス | - | なし |

## メンテナンスモード制御

メンテナンスモードは **StepFunctions のタグ** で制御されます：

- タグキー: `Maintenance`
- タグ値: `true` （メンテナンス中）/ `false` または未設定 （通常運用）

## 必要な AWS 権限

Lambda 実行ロールには以下の権限が必要です：

### S3 権限
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::your-bucket-name",
                "arn:aws:s3:::your-bucket-name/*"
            ]
        }
    ]
}
```

### Step Functions 権限
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "states:SendTaskSuccess",
                "states:SendTaskFailure",
                "states:DescribeStateMachine",
                "states:ListTagsForResource"
            ],
            "Resource": "*"
        }
    ]
}
```

## 使用方法

### 1. Step Functions ワークフローでの統合

```json
{
  "Comment": "メンテナンス対応可能なワークフロー",
  "StartAt": "MaintenanceCheck",
  "States": {
    "MaintenanceCheck": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:region:account:function:SfnPauser",
      "Parameters": {
        "taskToken.$": "$$.Task.Token",
        "stateMachineArn.$": "$$.StateMachine.Id"
      },
      "Next": "BusinessLogic"
    },
    "BusinessLogic": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:region:account:function:YourBusinessFunction",
      "End": true
    }
  }
}
```

### 2. メンテナンスモードの切り替え

```bash
# メンテナンスモード有効化（StepFunctions にタグを設定）
aws stepfunctions tag-resource \
    --resource-arn arn:aws:states:region:account:stateMachine:YourStateMachine \
    --tags key=Maintenance,value=true

# メンテナンスモード無効化（タグを削除）
aws stepfunctions untag-resource \
    --resource-arn arn:aws:states:region:account:stateMachine:YourStateMachine \
    --tag-keys Maintenance
```

## 応答形式

### メンテナンスモード有効時
```json
{
    "status": "maintenance",
    "saved_token_key": "your-prefix/YourStateMachine/12345678-1234-1234-1234-123456789abc.json"
}
```

### メンテナンスモード無効時
```json
{
    "status": "proceeding",
    "resumed_tokens": 3
}
```

## S3 保存形式

保存されるタスクトークンのファイル構造：

```
{Prefix}/{StateMachineName}/{UUID}.json
```

例：
```
stepfunctions-tokens/OrderProcessing/12345678-1234-1234-1234-123456789abc.json
stepfunctions-tokens/UserRegistration/87654321-4321-4321-4321-cba987654321.json
```

各JSONファイルの内容：
```json
{
    "taskToken": "AQCAAo...",
    "timestamp": "2023-12-01T12:34:56.789Z"
}
```

## デプロイ方法

### 1. パッケージの作成
```bash
# 依存関係のインストール
pip install -r requirements.txt -t .

# Lambda デプロイパッケージの作成
zip -r sfn-pauser.zip lambda_function.py boto3/ botocore/ ...
```

### 2. Lambda 関数の作成
```bash
aws lambda create-function \
    --function-name SfnPauser \
    --zip-file fileb://sfn-pauser.zip \
    --handler lambda_function.lambda_handler \
    --runtime python3.13 \
    --role arn:aws:iam::account:role/lambda-execution-role \
    --environment Variables='{Bucket=your-bucket,Prefix=stepfunctions-tokens/}'
```

### 3. deploy.sh を使用した自動デプロイ
```bash
./deploy.sh your-bucket-name arn:aws:iam::123456789012:role/lambda-execution-role
```

## 注意事項

- メンテナンスモード中に保存されたタスクトークンには有効期限があります（通常1年）
- S3 バケットは Lambda 関数と同じリージョンに作成することを推奨します
- 大量のタスクが保存される場合は、S3 の料金にご注意ください
- Lambda 関数のタイムアウト設定を適切に設定してください（推奨：5分以上）

## トラブルシューティング

### よくある問題

1. **権限エラー**: IAM ロールに必要な権限が設定されているか確認
2. **S3 エラー**: バケット名と権限設定を確認
3. **タスクトークン期限切れ**: 長期間メンテナンスモードを継続した場合に発生

### ログの確認
CloudWatch Logs で Lambda 関数の実行ログを確認できます。

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。