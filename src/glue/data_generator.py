from datetime import datetime
from faker import Faker
import random
import pytz
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, FloatType


spark = SparkSession.builder \
    .appName("GenerateSiteIDs") \
    .getOrCreate()

min_sites = 1
max_sites = 100


num_sites = random.randint(min_sites, max_sites)
print(f"Generating {num_sites} site_ids...")
current_time = str(datetime.now())
output_path = f"s3://mock-energy-data/rawdata/{current_time}"


schema = StructType([
    StructField("site_id", StringType(), False),
    StructField("timestamp", StringType(), False),
    StructField("energy_generated_kwh", FloatType(), False),
    StructField("energy_consumed_kwh", FloatType(), False),
])

def generate_data(record):
    faker = Faker()
    site_id = f"site_id{record + 1:03}"
    return (
        site_id,
        str(faker.date_time(tzinfo=pytz.UTC).isoformat()),
        faker.pyfloat(left_digits=2, right_digits=2, min_value=-20, max_value=100),
        faker.pyfloat(left_digits=2, right_digits=2, min_value=-20, max_value=100),
    )


df_data = spark.sparkContext.parallelize(range(num_sites)).map(generate_data).toDF(schema)

df_data.coalesce(1).write.mode("overwrite").json(output_path)
