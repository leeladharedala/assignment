import json
import urllib
import boto3
from decimal import Decimal
import os

s3client = boto3.client('s3')
sns_client = boto3.client('sns')
dynamodb = boto3.resource('dynamodb')

table = dynamodb.Table('EnergySiteData')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def lambda_handler(event, context):
    print(event)
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        key = urllib.parse.unquote_plus(key)
        print(bucket, key)
        # bucket = 'mock-energy-data'
        # key = 'RawData/2025-06-09 18:26:46.788422/part-00000-10c46d34-f2f3-4db2-88ba-4fdf93d8c7c6-c000.json'
        response = s3client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        lines = content.strip().split('\n')
        data = [json.loads(line) for line in lines]
        for site in data:
            site_id = site.get('site_id')
            timestamp = site.get('timestamp')
            energy_generated_kwh = site.get('energy_generated_kwh')
            energy_consumed_kwh = site.get('energy_consumed_kwh')
            net_energy_kwh = energy_generated_kwh - energy_consumed_kwh
            net_energy_kwh = round(net_energy_kwh, 2)
            anomaly = energy_generated_kwh < 0 or energy_consumed_kwh < 0

            table.put_item(Item={
            'site_id': site_id,
            'timestamp': timestamp,
            'energy_generated_kwh': Decimal(str(energy_generated_kwh)),
            'energy_consumed_kwh': Decimal(str(energy_consumed_kwh)),
            'net_energy_kwh': Decimal(str(net_energy_kwh)),
            'anomaly': anomaly
            })

            if anomaly:
                alert_notification = (
                    f"!!! Energy Anomaly Detected!!!\n"
                    f"site_id: {site_id}\n"
                    f"timestamp: {timestamp}\n"
                    f"energy_generated_kwh: {energy_generated_kwh}\n"
                    f"energy_consumed_kwh: {energy_consumed_kwh}"
                )
                sns_client.publish(
                TopicArn = SNS_TOPIC_ARN,
                Subject = "Anomaly Alert",
                Message = alert_notification
                )

    return {
        "statusCode": 200,
        "body": json.dumps("Success")
    }