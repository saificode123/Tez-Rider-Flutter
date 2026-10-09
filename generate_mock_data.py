import csv
import random
from datetime import datetime, timedelta
import os

def get_random_date(days_back=30):
    now = datetime.utcnow()
    delta = timedelta(days=random.randint(0, days_back), hours=random.randint(0, 23), minutes=random.randint(0, 59))
    return (now - delta).strftime("%Y-%m-%d %H:%M:%S")

os.makedirs("mock_data", exist_ok=True)

def write_csv(filename, data):
    if not data: return
    keys = data[0].keys()
    with open(f"mock_data/{filename}.csv", 'w', newline='', encoding='utf-8') as f:
        dict_writer = csv.DictWriter(f, fieldnames=keys)
        dict_writer.writeheader()
        dict_writer.writerows(data)

# Known ID ranges from previous generation:
customers = list(range(1, 21))
vendors_list = list(range(21, 41))
riders_list = list(range(41, 61))
orders = list(range(1, 51))
products = list(range(1, 100))

# 1. riders
riders = []
for idx, r_id in enumerate(riders_list):
    riders.append({
        "id": idx + 1,
        "userid": r_id,
        "is_available": "true" if random.random() > 0.3 else "false",
        "latitude": round(random.uniform(33.6, 33.75), 6),
        "longitude": round(random.uniform(72.9, 73.1), 6)
    })

# 2. vendors
vendors = []
for idx, v_id in enumerate(vendors_list):
    vendors.append({
        "id": idx + 1,
        "user_id": v_id,
        "store_name": f"Vendor Store {v_id}",
        "is_active": "true"
    })

# 3. stores
stores = []
for idx, v_id in enumerate(vendors_list):
    stores.append({
        "id": idx + 1,
        "vendor_id": v_id,
        "name": f"Main Branch {v_id}",
        "address": "123 Delivery Street, Islamabad"
    })

# 4. rider_assignments
rider_assignments = []
for idx, o_id in enumerate(orders[:20]):
    rider_assignments.append({
        "id": idx + 1,
        "assignid": idx + 1,
        "riderid": random.choice(riders_list),
        "orderid": o_id,
        "status": random.choice(["Pending", "Accepted", "Completed"])
    })

write_csv("riders", riders)
write_csv("vendors", vendors)
write_csv("stores", stores)
write_csv("rider_assignments", rider_assignments)

print("Generated mock data specifically for the new remaining tables (riders, vendors, stores, rider_assignments)!")
