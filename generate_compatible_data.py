"""
TezRider – Compatible Mock Data Generator
Generates CSVs that exactly match the Supabase schema:
  schema.sql        → users, products, orders, vendor_orders, order_items,
                       notifications, gps_locations, disputes,
                       tailoring_requests, chat_rooms, messages
  fix_riders_schema → riders, vendors, stores, rider_assignments

Import order (respects FK dependencies):
  1. users
  2. products, riders, vendors, stores
  3. orders
  4. vendor_orders, rider_assignments
  5. order_items
  6. notifications, gps_locations, disputes,
     tailoring_requests, chat_rooms
  7. messages
"""

import csv, random, os
from datetime import datetime, timedelta

OUT = "mock_data_compatible"
os.makedirs(OUT, exist_ok=True)


def rdate(days_back=60):
    dt = datetime.utcnow() - timedelta(
        days=random.randint(0, days_back),
        hours=random.randint(0, 23),
        minutes=random.randint(0, 59),
    )
    return dt.strftime("%Y-%m-%d %H:%M:%S+00")


def write_csv(name, rows):
    if not rows:
        return
    path = f"{OUT}/{name}.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)
    print(f"  OK {name}.csv  ({len(rows)} rows)")


# ── ID pools ──────────────────────────────────────────────────────────────────
CUSTOMER_IDS = list(range(1, 21))   # 1-20
VENDOR_IDS   = list(range(21, 31))  # 21-30
RIDER_IDS    = list(range(31, 41))  # 31-40
ADMIN_ID     = 41

PRODUCT_IDS  = list(range(1, 61))   # 60 products
ORDER_IDS    = list(range(1, 51))   # 50 orders

# ── 1. USERS ──────────────────────────────────────────────────────────────────
customer_names = [
    "Ayesha Khan", "Ali Hassan", "Sara Ahmed", "Bilal Raza", "Hina Malik",
    "Usman Sheikh", "Zara Siddiqui", "Hamza Javed", "Nadia Iqbal", "Farhan Butt",
    "Amna Chaudhry", "Arslan Nawaz", "Maham Tahir", "Sohaib Mirza", "Rabia Aslam",
    "Talha Qureshi", "Iqra Yousaf", "Danish Baig", "Mehwish Rao", "Waseem Zafar",
]
vendor_names = [
    "Spice Garden", "Fresh Mart", "MediQuick Pharmacy", "Thrift Palace",
    "Preloved Finds", "Gift Haven", "Desi Delights", "Green Grocer",
    "Quick Bites", "Fashion Forward",
]
rider_names = [
    "Tariq Hussain", "Amir Saleem", "Shoaib Khan", "Imran Ashraf",
    "Nabeel Ahmed", "Kashif Ali", "Asad Mehmood", "Rehan Akhtar",
    "Zubair Hassan", "Majid Raza",
]

users = []
for i, cid in enumerate(CUSTOMER_IDS):
    users.append({
        "id": cid,
        "name": customer_names[i],
        "email": f"customer{cid}@tezrider.com",
        "phone": f"+9230{random.randint(10000000,99999999)}",
        "role": "customer",
        "verification_status": "approved",
        "profile_image": "",
        "created_at": rdate(90),
    })
for i, vid in enumerate(VENDOR_IDS):
    users.append({
        "id": vid,
        "name": vendor_names[i],
        "email": f"vendor{vid}@tezrider.com",
        "phone": f"+9233{random.randint(10000000,99999999)}",
        "role": "vendor",
        "verification_status": "approved",
        "profile_image": "",
        "created_at": rdate(90),
    })
for i, rid in enumerate(RIDER_IDS):
    users.append({
        "id": rid,
        "name": rider_names[i],
        "email": f"rider{rid}@tezrider.com",
        "phone": f"+9232{random.randint(10000000,99999999)}",
        "role": "rider",
        "verification_status": "approved",
        "profile_image": "",
        "created_at": rdate(90),
    })
users.append({
    "id": ADMIN_ID,
    "name": "Super Admin",
    "email": "admin@tezrider.com",
    "phone": "+923001234567",
    "role": "admin",
    "verification_status": "approved",
    "profile_image": "",
    "created_at": rdate(120),
})

# ── 2. PRODUCTS ───────────────────────────────────────────────────────────────
category_products = {
    "Food":      ["Chicken Biryani", "Beef Karahi", "Daal Makhani", "Seekh Kabab Platter",
                  "Nihari", "Haleem", "Paye", "Mutton Pulao", "Mix Grill", "Qeema Naan"],
    "Grocery":   ["Basmati Rice 5kg", "Atta 10kg", "Cooking Oil 1L", "Sugar 1kg",
                  "Milk 1L", "Tea Leaves 250g", "Daal Chana 500g", "Tomatoes 1kg",
                  "Onions 2kg", "Potatoes 2kg"],
    "Pharmacy":  ["Panadol Extra 10s", "ORS Sachet", "Vitamin C 1000mg", "Antibiotic Cream",
                  "Bandages Pack", "Hand Sanitizer 250ml", "Cough Syrup 100ml",
                  "Thermometer Digital", "BP Monitor", "Antacid 20s"],
    "Thrift":    ["Denim Jacket (M)", "Leather Bag", "Formal Shoes", "Linen Kurti",
                  "Running Shoes", "Silk Dupatta", "Winter Coat", "Casual Watch",
                  "Canvas Bag", "Embroidered Shawl"],
    "Preloved":  ["iPhone 12 (Good)", "Samsung A32", "Laptop HP 8GB", "Sony Earbuds",
                  "Kindle Paperwhite", "Canon Camera", "MacBook Air 2019",
                  "Apple Watch SE", "JBL Speaker", "Ring Light 26cm"],
    "Gifts":     ["Chocolate Box", "Flower Bouquet", "Birthday Cake", "Scented Candles Set",
                  "Gift Hamper (Small)", "Teddy Bear 30cm", "Photo Frame",
                  "Perfume Gift Set", "Coffee Mug Pair", "Personalized Notebook"],
}
categories_list = list(category_products.keys())

products = []
pid = 1
for cat, names in category_products.items():
    vendor_id = random.choice(VENDOR_IDS)
    for pname in names:
        base = random.choice([150, 200, 250, 350, 500, 750, 1000, 1500, 2000, 3000])
        products.append({
            "id": pid,
            "vendor_id": vendor_id,
            "category": cat,
            "name": pname,
            "description": f"Fresh {pname} available for same-day delivery.",
            "price": base + random.randint(0, 99),
            "image_url": f"https://source.unsplash.com/200x200/?{pname.split()[0].lower()}",
            "is_available": "true",
            "created_at": rdate(60),
        })
        pid += 1

# ── 3. ORDERS ─────────────────────────────────────────────────────────────────
addresses = [
    "House 12, Street 5, F-7/2, Islamabad",
    "Plot 34, G-10 Markaz, Islamabad",
    "Flat 201, Gulberg Residencia, Islamabad",
    "Shop 5, Blue Area, Islamabad",
    "Sector I-8/3, Islamabad",
    "Bahria Town Phase 4, Rawalpindi",
    "Saddar Bazaar, Rawalpindi",
    "DHA Phase 2, Islamabad",
    "Model Town, Rawalpindi",
    "PWD Housing Scheme, Islamabad",
]
statuses = ["placed", "confirmed", "preparing", "on_the_way", "delivered"]
status_weights = [0.1, 0.15, 0.2, 0.15, 0.4]

orders = []
for oid in ORDER_IDS:
    cid = random.choice(CUSTOMER_IDS)
    vid = random.choice(VENDOR_IDS)
    rid = random.choice(RIDER_IDS)
    amt = random.randint(300, 5000)
    status = random.choices(statuses, weights=status_weights)[0]
    addr = random.choice(addresses)
    is_gift = random.random() < 0.15
    orders.append({
        "id": oid,
        "user_id": cid,
        "vendor_id": vid,
        "rider_id": rid,
        "amount": amt,
        "fare": random.choice([50, 80, 100, 120, 150]),
        "order_status": status,
        "payment_method": random.choice(["COD", "JazzCash", "EasyPaisa", "Card"]),
        "delivery_address": addr,
        "delivery_lat": round(random.uniform(33.60, 33.75), 6),
        "delivery_lng": round(random.uniform(72.90, 73.10), 6),
        "is_gift": "true" if is_gift else "false",
        "recipient_name": "Ali Raza" if is_gift else "",
        "recipient_phone": "+923111234567" if is_gift else "",
        "gift_message": "Happy Birthday!" if is_gift else "",
        "created_at": rdate(30),
    })

# ── 4. VENDOR_ORDERS ──────────────────────────────────────────────────────────
vo_statuses = ["pending", "accepted", "preparing", "ready", "completed"]
vendor_orders = []
for vo_id, order in enumerate(orders, start=1):
    vendor_orders.append({
        "id": vo_id,
        "order_id": order["id"],
        "vendor_id": order["vendor_id"],
        "sub_total": int(order["amount"]) - random.randint(0, 50),
        "status": vo_statuses[statuses.index(order["order_status"])] if order["order_status"] in statuses else "pending",
        "created_at": order["created_at"],
    })

# ── 5. ORDER_ITEMS ────────────────────────────────────────────────────────────
order_items = []
oi_id = 1
for vo in vendor_orders:
    item_count = random.randint(1, 4)
    for _ in range(item_count):
        prod = random.choice(products)
        order_items.append({
            "id": oi_id,
            "vendor_order_id": vo["id"],
            "product_id": prod["id"],
            "quantity": random.randint(1, 3),
            "price_at_time": prod["price"],
            "created_at": vo["created_at"],
        })
        oi_id += 1

# ── 6. NOTIFICATIONS ──────────────────────────────────────────────────────────
notif_templates = [
    ("Order Confirmed!", "Your order #{oid} has been confirmed by the vendor.", "order"),
    ("Rider Assigned", "A rider is on the way to pick up your order #{oid}.", "order"),
    ("Order Delivered", "Your order #{oid} has been delivered. Enjoy!", "order"),
    ("Payment Received", "Payment of PKR {amt} received successfully.", "payment"),
    ("New Order!", "You have a new order #{oid} from a customer.", "vendor"),
    ("Special Offer", "Get 20% off on your next order. Use code TEZOFF.", "promo"),
]
all_user_ids = CUSTOMER_IDS + VENDOR_IDS + RIDER_IDS + [ADMIN_ID]
notifications = []
for n_id in range(1, 81):
    uid = random.choice(all_user_ids)
    title, msg_tmpl, ntype = random.choice(notif_templates)
    oid = random.choice(ORDER_IDS)
    amt = random.randint(300, 5000)
    notifications.append({
        "id": n_id,
        "user_id": uid,
        "title": title,
        "message": msg_tmpl.format(oid=f"TR-{oid:04d}", amt=amt),
        "type": ntype,
        "is_read": "true" if random.random() > 0.4 else "false",
        "created_at": rdate(20),
    })

# ── 7. GPS_LOCATIONS ──────────────────────────────────────────────────────────
# rider_id is TEXT UNIQUE in this table
gps_locations = []
for i, rid in enumerate(RIDER_IDS, start=1):
    gps_locations.append({
        "id": i,
        "rider_id": str(rid),          # TEXT column
        "latitude": round(random.uniform(33.60, 33.75), 6),
        "longitude": round(random.uniform(72.90, 73.10), 6),
        "updated_at": rdate(1),
    })

# ── 8. DISPUTES ───────────────────────────────────────────────────────────────
dispute_types = [
    "Late Delivery", "Wrong Item Delivered", "Missing Item",
    "Payment Not Received", "Damaged Item", "Rider Misconduct",
    "Vendor Non-Responsive", "Refund Request",
]
disputes = []
for d_id in range(1, 16):
    disputes.append({
        "id": d_id,
        "type": random.choice(dispute_types),
        "by": f"customer{random.choice(CUSTOMER_IDS)}@tezrider.com",
        "status": random.choice(["Open", "Under Review", "Resolved", "Closed"]),
        "created_at": rdate(30),
    })

# ── 9. TAILORING_REQUESTS ─────────────────────────────────────────────────────
tailoring_instructions = [
    "Slim fit, 38 chest, 32 waist, remove extra buttons.",
    "Loose kurta, length 42 inches, wide sleeves.",
    "Alter hemline 2 inches up, add lining.",
    "Take in waist by 1.5 inches, shorten by 3 inches.",
    "Custom embroidery on collar, size M.",
]
tailoring_requests = []
for tr_id in range(1, 16):
    tailoring_requests.append({
        "id": tr_id,
        "vendor_id": random.choice(VENDOR_IDS),
        "customer_id": random.choice(CUSTOMER_IDS),
        "instructions": random.choice(tailoring_instructions),
        "status": random.choice(["pending", "in_progress", "completed", "cancelled"]),
        "created_at": rdate(20),
    })

# ── 10. CHAT_ROOMS ────────────────────────────────────────────────────────────
chat_rooms = []
used_pairs = set()
cr_id = 1
while len(chat_rooms) < 20:
    u1 = random.choice(CUSTOMER_IDS)
    u2 = random.choice(VENDOR_IDS + RIDER_IDS)
    pair = (min(u1, u2), max(u1, u2))
    if pair in used_pairs:
        continue
    used_pairs.add(pair)
    chat_rooms.append({
        "id": cr_id,
        "user1_id": u1,
        "user2_id": u2,
        "created_at": rdate(30),
    })
    cr_id += 1

# ── 11. MESSAGES ──────────────────────────────────────────────────────────────
convo_texts = [
    "Hi, when will my order arrive?",
    "Your order is being prepared now.",
    "I am on my way, will reach in 10 minutes.",
    "Can you please hurry? I have been waiting.",
    "Sorry for the delay, traffic is heavy today.",
    "Thank you! Order received in good condition.",
    "One item is missing from my order.",
    "We will send the missing item shortly.",
    "Is the item still available?",
    "Yes, it is in stock. Add to cart now!",
    "Please pack it carefully, it is fragile.",
    "Noted! We always ensure careful packaging.",
]
messages = []
for m_id in range(1, 61):
    room = random.choice(chat_rooms)
    sender = random.choice([room["user1_id"], room["user2_id"]])
    messages.append({
        "id": m_id,
        "room_id": room["id"],
        "sender_id": sender,
        "text": random.choice(convo_texts),
        "created_at": rdate(10),
    })

# ── 12. RIDERS (fix_riders_schema) ───────────────────────────────────────────
riders_table = []
for i, rid in enumerate(RIDER_IDS, start=1):
    available = random.random() > 0.3
    riders_table.append({
        "id": i,
        "userid": rid,
        "is_available": "true" if available else "false",
        "latitude": round(random.uniform(33.60, 33.75), 6),
        "longitude": round(random.uniform(72.90, 73.10), 6),
        "isavailable": "true" if available else "false",   # duplicate column in schema
    })

# ── 13. VENDORS (fix_riders_schema) ──────────────────────────────────────────
store_suffixes = ["Restaurant", "Mart", "Store", "Shop", "Pharmacy", "Outlet"]
vendors_table = []
for i, vid in enumerate(VENDOR_IDS, start=1):
    vendors_table.append({
        "id": i,
        "user_id": vid,
        "store_name": f"{vendor_names[i-1]} {random.choice(store_suffixes)}",
        "is_active": "true",
    })

# ── 14. STORES (fix_riders_schema) ────────────────────────────────────────────
store_addresses = [
    "Shop 3, Jinnah Super Market, F-7 Islamabad",
    "Kiosk 12, Blue Area, Islamabad",
    "Stall 5, G-9 Markaz, Islamabad",
    "Unit 7, Centaurus Mall, Islamabad",
    "Plot 9, Saddar Rawalpindi",
    "Booth 2, Bahria Town Phase 7",
    "Ground Floor, Packages Mall, Lahore",
    "Shop 22, I-8 Markaz, Islamabad",
    "Corner Shop, DHA Phase 2",
    "Main Branch, F-10 Markaz, Islamabad",
    "Express Outlet, G-11/3, Islamabad",
    "Market Lane 4, Pindi",
    "Arcade 5, E-11, Islamabad",
    "Shop 1, Melody Market, Islamabad",
    "Street 7, I-9 Industrial, Islamabad",
]
stores_table = []
for s_id in range(1, 16):
    stores_table.append({
        "id": s_id,
        "vendor_id": random.choice(VENDOR_IDS),
        "name": f"{random.choice(vendor_names)} Branch {s_id}",
        "address": store_addresses[s_id - 1],
    })

# ── 15. RIDER_ASSIGNMENTS (fix_riders_schema) ────────────────────────────────
ra_statuses = ["Pending", "Accepted", "Picked Up", "Completed", "Cancelled"]
rider_assignments = []
for ra_id, oid in enumerate(ORDER_IDS[:35], start=1):
    rider_assignments.append({
        "id": ra_id,
        "assignid": ra_id,
        "riderid": random.choice(RIDER_IDS),
        "orderid": oid,
        "status": random.choice(ra_statuses),
    })

# ── Write all CSVs ────────────────────────────────────────────────────────────
print("\nGenerating CSVs in ./mock_data_compatible/")
print("=" * 50)
print("-- schema.sql tables --")
write_csv("1_users",               users)
write_csv("2_products",            products)
write_csv("3_orders",              orders)
write_csv("4_vendor_orders",       vendor_orders)
write_csv("5_order_items",         order_items)
write_csv("6_notifications",       notifications)
write_csv("7_gps_locations",       gps_locations)
write_csv("8_disputes",            disputes)
write_csv("9_tailoring_requests",  tailoring_requests)
write_csv("10_chat_rooms",         chat_rooms)
write_csv("11_messages",           messages)
print("-- fix_riders_schema tables --")
write_csv("12_riders",             riders_table)
write_csv("13_vendors",            vendors_table)
write_csv("14_stores",             stores_table)
write_csv("15_rider_assignments",  rider_assignments)

print("\n" + "=" * 50)
print("Done! 15 CSV files ready.")
print()
print("IMPORT ORDER in Supabase Table Editor:")
print("  1. users")
print("  2. products, riders, vendors, stores")
print("  3. orders")
print("  4. vendor_orders, rider_assignments")
print("  5. order_items")
print("  6. notifications, gps_locations, disputes,")
print("     tailoring_requests, chat_rooms")
print("  7. messages")
print()
print("Test logins:")
print("  Admin  : admin@tezrider.com")
print("  Vendor : vendor21@tezrider.com  (IDs 21-30)")
print("  Rider  : rider31@tezrider.com   (IDs 31-40)")
print("  Cust.  : customer1@tezrider.com (IDs 1-20)")
