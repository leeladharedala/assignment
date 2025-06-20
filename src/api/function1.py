from fastapi import FastAPI, Query, HTTPException
from mangum import Mangum
import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError, BotoCoreError
import logging
app = FastAPI()

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('EnergySiteData')

@app.get("/records/{site_id}")
def get_records(site_id: str, start: str = Query(...), end: str = Query(...)):
    if start>end:
        raise HTTPException(status_code= 400, detail="Please check and enter proper timestamp range")
    try:
        response = table.query(
            KeyConditionExpression=Key('site_id').eq(site_id) & Key('timestamp').between(start, end)
        )
        items = response.get("Items", [])

        if not items:
            raise HTTPException(status_code=404, detail=f"No record found for site_id '{site_id}' in the given time frame.")

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



