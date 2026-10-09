import csv
import random
import os
from datetime import datetime, timedelta

def get_random_date(days_back=30):
    now = datetime.utcnow()
    delta = timedelta(days=random.randint(0, days_back), hours=random.randint(0, 23), minutes=random.randint(0, 59))
    return (now - delta).strftime("%Y-%m-%d %H:%M:%S")

os.makedirs("mock_data_extra", exist_ok=True)

def write_csv(filename, data):
    if not data: return
    keys = data[0].keys()
    with open(f"mock_data_extra/{filename}.csv", 'w', newline='', encoding='utf-8') as f:
        dict_writer = csv.DictWriter(f, fieldnames=keys)
        dict_writer.writeheader()
        dict_writer.writerows(data)

# Common IDs
user_ids = list(range(1, 51))
order_ids = list(range(1, 51))
product_ids = list(range(1, 100))
vendor_ids = list(range(1, 21))
rider_ids = list(range(1, 21))

# 1. admin
admin = [{"id": 1, "name": "Super Admin", "email": "admin@tezrider.com", "role": "admin", "created_at": get_random_date()}]

# 2. analytics
analytics = [{"id": i+1, "metric_name": random.choice(["Daily Active Users", "Total Revenue", "Orders Completed"]), "metric_value": random.randint(100, 10000), "recorded_at": get_random_date()} for i in range(20)]

# 3. audit_log
audit_log = [{"id": i+1, "action": random.choice(["USER_LOGIN", "ORDER_CREATED", "PAYMENT_PROCESSED"]), "user_id": random.choice(user_ids), "details": "Action performed successfully", "created_at": get_random_date()} for i in range(30)]

# 4. cart
cart = [{"id": i+1, "user_id": user_id, "created_at": get_random_date()} for i, user_id in enumerate(user_ids[:20])]

# 5. cart_items
cart_items = [{"id": i+1, "cart_id": random.choice(range(1, 21)), "product_id": random.choice(product_ids), "quantity": random.randint(1, 5)} for i in range(50)]

# 6. categories
categories_list = ["Food", "Grocery", "Pharmacy", "Thrift", "Preloved", "Gifts"]
categories = [{"id": i+1, "name": cat, "icon_url": f"https://example.com/icon_{cat.lower()}.png"} for i, cat in enumerate(categories_list)]

# 7. chat_messages
chat_messages = [{"id": i+1, "room_id": random.randint(1, 15), "sender_id": random.choice(user_ids), "message": "Hello, checking my order status.", "created_at": get_random_date()} for i in range(40)]

# 8. chat_participants
chat_participants = [{"id": i+1, "room_id": random.randint(1, 15), "user_id": random.choice(user_ids)} for i in range(30)]

# 9. complaints
complaints = [{"id": i+1, "user_id": random.choice(user_ids), "subject": "Late Delivery", "description": "The rider arrived 30 minutes late.", "status": random.choice(["Open", "Resolved"]), "created_at": get_random_date()} for i in range(15)]

# 10. customer
customer = [{"id": i+1, "user_id": uid, "name": f"Customer {uid}", "email": f"customer{uid}@example.com", "phone": "+923001234567", "address": "123 Street, City"} for i, uid in enumerate(user_ids[:20])]

# 11. delivery_proof
delivery_proof = [{"id": i+1, "order_id": oid, "rider_id": random.choice(rider_ids), "image_url": "https://example.com/proof.jpg", "created_at": get_random_date()} for i, oid in enumerate(order_ids[:20])]

# 12. favourite
favourite = [{"id": i+1, "user_id": random.choice(user_ids), "product_id": random.choice(product_ids)} for i in range(30)]

# 13. feedback
feedback = [{"id": i+1, "order_id": random.choice(order_ids), "user_id": random.choice(user_ids), "rating": random.randint(3, 5), "comment": "Great service!", "created_at": get_random_date()} for i in range(25)]

# 14. gifts
gifts = [{"id": i+1, "order_id": random.choice(order_ids), "recipient_name": "Ali", "recipient_phone": "+923111234567", "message": "Happy Birthday!"} for i in range(10)]

# 15. payment
payment = [{"id": i+1, "order_id": oid, "amount": random.randint(500, 5000), "method": random.choice(["COD", "Card", "JazzCash"]), "status": random.choice(["Pending", "Completed"]), "created_at": get_random_date()} for i, oid in enumerate(order_ids)]

# 16. reviews
reviews = [{"id": i+1, "product_id": random.choice(product_ids), "user_id": random.choice(user_ids), "rating": random.randint(4, 5), "comment": "Highly recommended!", "created_at": get_random_date()} for i in range(40)]

# 17. rider_assignments
rider_assignments = [{"id": i+1, "order_id": oid, "rider_id": random.choice(rider_ids), "status": random.choice(["Assigned", "Picked Up", "Delivered"])} for i, oid in enumerate(order_ids[:30])]

# 18. riders
riders = [{"id": i+1, "user_id": rid, "name": f"Rider {rid}", "phone": "+923221234567", "vehicle_details": "Honda CD70", "is_available": "true"} for i, rid in enumerate(rider_ids)]

# 19. stores
stores = [{"id": i+1, "vendor_id": random.choice(vendor_ids), "name": f"Store {i+1}", "address": "Market Square", "is_open": "true"} for i in range(15)]

# 20. vendor
vendor = [{"id": i+1, "user_id": vid, "business_name": f"Business {vid}", "email": f"vendor{vid}@store.com", "phone": "+923331234567"} for i, vid in enumerate(vendor_ids)]

# Write all to CSV
write_csv("admin", admin)
write_csv("analytics", analytics)
write_csv("audit_log", audit_log)
write_csv("cart", cart)
write_csv("cart_items", cart_items)
write_csv("categories", categories)
write_csv("chat_messages", chat_messages)
write_csv("chat_participants", chat_participants)
write_csv("complaints", complaints)
write_csv("customer", customer)
write_csv("delivery_proof", delivery_proof)
write_csv("favourite", favourite)
write_csv("feedback", feedback)
write_csv("gifts", gifts)
write_csv("payment", payment)
write_csv("reviews", reviews)
write_csv("rider_assignments", rider_assignments)
write_csv("riders", riders)
write_csv("stores", stores)
write_csv("vendor", vendor)

print("Generated all 20 extra tables successfully!")
