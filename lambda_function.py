import os
import json
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

s3_client = boto3.client('s3')
sf_client = boto3.client('stepfunctions')

def lambda_handler(event, context):
    """
    StepFunctions のメンテナンスモード管理用 Lambda 関数
    
    Args:
        event: Lambda イベント（taskToken, stateMachineArn を含む）
        context: Lambda コンテキスト
    
    Returns:
        dict: 実行結果
    """
    bucket = os.environ.get('Bucket')
    prefix = os.environ.get('Prefix')
    task_token = event.get('taskToken')
    state_machine_arn = event.get('stateMachineArn')

    if not task_token:
        raise ValueError("taskToken is missing from the input payload.")
    if not state_machine_arn:
        raise ValueError("stateMachineArn is missing from the input payload.")

    # ステートマシンの名前とタグを取得
    sm_info = sf_client.describe_state_machine(stateMachineArn=state_machine_arn)
    state_machine_name = sm_info['name']
    tags_response = sf_client.list_tags_for_resource(resourceArn=state_machine_arn)
    tags = {tag['key']: tag['value'] for tag in tags_response.get('tags', [])}

    maintenance_flag = tags.get('Maintenance', 'false').lower()

    s3_prefix = f"{prefix.rstrip('/')}/{state_machine_name}"

    if maintenance_flag == 'true':
        # メンテナンス中：UUIDをキーにしてトークンを保存
        token_id = str(uuid.uuid4())
        s3_key = f"{s3_prefix}/{token_id}.json"
        payload = {
            "taskToken": task_token,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        store_token_in_s3(bucket, s3_key, payload)
        print(f"メンテナンス中のため、タスクトークンを {s3_key} に保存しました")
        return {
            "status": "maintenance",
            "saved_token_key": s3_key
        }

    else:
        # メンテナンス外：保存されたトークンをすべて再開し削除
        tokens = get_token_list_from_s3(bucket, s3_prefix)
        resumed_count = 0

        for token, key in tokens:
            try:
                sf_client.send_task_success(
                    taskToken=token,
                    output=json.dumps({"status": "resumed"})
                )
                delete_token_from_s3(bucket, key)
                resumed_count += 1
                print(f"再開完了: {key}")
            except ClientError as e:
                print(f"{key} の再開に失敗しました: {e}")

        # 自身のタスクも成功として継続
        sf_client.send_task_success(
            taskToken=task_token,
            output=json.dumps({"status": "proceeding"})
        )
        print("自身のタスクも成功として継続しました")

        return {
            "status": "proceeding",
            "resumed_tokens": resumed_count
        }

def store_token_in_s3(bucket, key, data):
    """
    タスクトークンを S3 に保存
    
    Args:
        bucket (str): S3 バケット名
        key (str): S3 オブジェクトキー
        data (dict): 保存するデータ
    """
    try:
        s3_client.put_object(Bucket=bucket, Key=key, Body=json.dumps(data))
    except ClientError as e:
        print(f"S3への保存に失敗: {e}")
        raise

def get_token_list_from_s3(bucket, prefix):
    """
    S3 から保存されたタスクトークンのリストを取得
    
    Args:
        bucket (str): S3 バケット名
        prefix (str): S3 オブジェクトキーのプレフィックス
    
    Returns:
        list: (taskToken, key) のタプルのリスト
    """
    tokens = []
    try:
        response = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)
        if 'Contents' not in response:
            return tokens

        for obj in response['Contents']:
            key = obj['Key']
            try:
                content = s3_client.get_object(Bucket=bucket, Key=key)['Body'].read()
                data = json.loads(content)
                if 'taskToken' in data:
                    tokens.append((data['taskToken'], key))
            except Exception as e:
                print(f"{key} の読み込みに失敗: {e}")
        return tokens

    except ClientError as e:
        print(f"S3からのトークン一覧取得に失敗: {e}")
        return []

def delete_token_from_s3(bucket, key):
    """
    S3 からタスクトークンを削除
    
    Args:
        bucket (str): S3 バケット名
        key (str): 削除する S3 オブジェクトキー
    """
    try:
        s3_client.delete_object(Bucket=bucket, Key=key)
    except ClientError as e:
        print(f"{key} の削除に失敗: {e}")