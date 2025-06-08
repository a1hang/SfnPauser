#!/bin/bash

# StepFunctions Pauser Lambda 関数デプロイスクリプト

set -e

# 設定
FUNCTION_NAME="SfnPauser"
RUNTIME="python3.13"
HANDLER="lambda_function.lambda_handler"
TIMEOUT=300
MEMORY_SIZE=128

# 色付きログ用の関数
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# 引数チェック
if [ $# -lt 2 ]; then
    echo "使用方法: $0 <S3_BUCKET_NAME> <IAM_ROLE_ARN> [PREFIX]"
    echo "例: $0 my-sfn-tokens-bucket arn:aws:iam::123456789012:role/lambda-execution-role stepfunctions-tokens/"
    exit 1
fi

S3_BUCKET=$1
IAM_ROLE_ARN=$2
PREFIX=${3:-"stepfunctions-tokens/"}

log_info "デプロイパラメータ:"
log_info "  関数名: $FUNCTION_NAME"
log_info "  S3バケット: $S3_BUCKET"
log_info "  IAMロール: $IAM_ROLE_ARN"
log_info "  プレフィックス: $PREFIX"

# 依存関係ディレクトリの作成
log_info "依存関係をインストールしています..."
rm -rf package/
mkdir -p package/

# requirements.txt が存在する場合のみ依存関係をインストール
if [ -f requirements.txt ]; then
    pip install -r requirements.txt -t package/
else
    log_warn "requirements.txt が見つかりません。boto3 は Lambda ランタイムに含まれているため、そのまま続行します。"
fi

# Lambda 関数ファイルをパッケージディレクトリにコピー
cp lambda_function.py package/

# デプロイパッケージの作成
log_info "デプロイパッケージを作成しています..."
cd package/
zip -r ../sfn-pauser-deployment.zip .
cd ..

# 既存の Lambda 関数の確認
log_info "既存の Lambda 関数を確認しています..."
if aws lambda get-function --function-name $FUNCTION_NAME >/dev/null 2>&1; then
    log_info "既存の関数を更新しています..."
    
    # 関数コードの更新
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://sfn-pauser-deployment.zip
    
    # 環境変数の更新
    aws lambda update-function-configuration \
        --function-name $FUNCTION_NAME \
        --environment Variables="{Bucket=$S3_BUCKET,Prefix=$PREFIX}" \
        --timeout $TIMEOUT \
        --memory-size $MEMORY_SIZE
    
    log_info "Lambda 関数を更新しました。"
else
    log_info "新しい Lambda 関数を作成しています..."
    
    # 新しい Lambda 関数の作成
    aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://sfn-pauser-deployment.zip \
        --handler $HANDLER \
        --runtime $RUNTIME \
        --role $IAM_ROLE_ARN \
        --environment Variables="{Bucket=$S3_BUCKET,Prefix=$PREFIX}" \
        --timeout $TIMEOUT \
        --memory-size $MEMORY_SIZE \
        --description "Step Functions メンテナンスモード管理関数"
    
    log_info "Lambda 関数を作成しました。"
fi

# S3 バケットの存在確認
log_info "S3 バケットの存在を確認しています..."
if aws s3 ls "s3://$S3_BUCKET" >/dev/null 2>&1; then
    log_info "S3 バケット '$S3_BUCKET' が確認できました。"
else
    log_warn "S3 バケット '$S3_BUCKET' が見つかりません。"
    read -p "バケットを作成しますか？ (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        aws s3 mb "s3://$S3_BUCKET"
        log_info "S3 バケット '$S3_BUCKET' を作成しました。"
    else
        log_error "S3 バケットが必要です。デプロイを中止します。"
        exit 1
    fi
fi

# 関数の ARN を取得して表示
FUNCTION_ARN=$(aws lambda get-function --function-name $FUNCTION_NAME --query 'Configuration.FunctionArn' --output text)

log_info "デプロイが完了しました！"
log_info "Lambda 関数 ARN: $FUNCTION_ARN"

# クリーンアップ
log_info "一時ファイルをクリーンアップしています..."
rm -f sfn-pauser-deployment.zip
rm -rf package/

log_info "メンテナンスモードを切り替えるには以下のコマンドを使用してください:"
echo ""
echo "# メンテナンスモード有効化（StepFunctions にタグを設定）"
echo "aws stepfunctions tag-resource --resource-arn YOUR_STATE_MACHINE_ARN --tags key=Maintenance,value=true"
echo ""
echo "# メンテナンスモード無効化（タグを削除）"
echo "aws stepfunctions untag-resource --resource-arn YOUR_STATE_MACHINE_ARN --tag-keys Maintenance"