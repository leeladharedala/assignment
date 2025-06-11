from fastapi import FastAPI, HTTPException
from mangum import Mangum
import boto3
from boto3.dynamodb.conditions import Key, Attr
import logging
from botocore.exceptions import ClientError, BotoCoreError

app = FastAPI()

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('EnergySiteData')


@app.get("/anomalies/{site_id}")
def get_anomalies(site_id: str):
    try:
        response = table.query(
            KeyConditionExpression=Key('site_id').eq(site_id),
            FilterExpression=Attr('anomaly').eq(True)
        )
        items = response.get("Items", [])

        if not items:
            raise HTTPException(status_code=404, detail=f"No anomaly found for {site_id}")

        return {"data": items}
    except HTTPException as e:
        raise e
    except ClientError as e:
        logger.error(f"AWS Client Error: {e}")
        raise HTTPException(status_code=500, detail=f"AWS Client Error: {e.response['Error']['Message']}.")
    except BotoCoreError as e:
        logger.error(f"AWS BotoCoreError: {e}")
        raise HTTPException(status_code=500, detail=f"Internal AWS Service Error.")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        raise HTTPException(status_code=500, detail=f"An unexpected error occurred while retrieving data.")


handler = Mangum(app)