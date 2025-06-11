from fastapi import FastAPI, HTTPException
from mangum import Mangum
import boto3
from boto3.dynamodb.conditions import Attr
import logging
from botocore.exceptions import ClientError, BotoCoreError
app = FastAPI()

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('EnergySiteData')

@app.get("/net_negative_energy")
def net_negative_energy():
    try:
        response = table.scan(
            FilterExpression = Attr('net_energy_kwh').lt(0)
        )
        items = response.get("Items", [])

        if not items:
            raise HTTPException(status_code=404, detail=f"No record found.")

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