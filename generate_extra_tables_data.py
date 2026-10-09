"""
TezRider – Extra Tables Mock Data Generator (schema-compatible v2)
Generates CSVs for 16 additional Supabase tables using actual column names.

BEFORE RUNNING:
  1. Run create_missing_tables.sql  (creates customer, favourite, payment, review)
  2. Run otp_delivery_setup.sql     (adds delivery_otp to orders)
  3. Then run this script and import the CSVs
"""

import csv, random, os, uuid
from datetime import datetime, timedelta

OUT = "mock_data_extra_compatible"
os.makedirs(OUT, exist_ok=True)

def rdate(days_back=60):
    dt = datetime.utcnow() - timedelta(
        days=random.randint(0, days_back),
        hours=random.randint(0, 23),
        minutes=random.randint(0, 59),
    )
    return dt.strftime("%Y-%m-%d %H:%M:%S+00")

def uid():
    return str(uuid.uuid4())

def write_csv(name, rows):
    if not rows:
        print(f"  SKIP {name}.csv  (no rows)")
        return
    path = f"{OUT}/{name}.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)
    print(f"  OK {name}.csv  ({len(rows)} rows)")

# ── ID pools (match main dataset: users 1-41, orders 1-50, products 1-60) ────
CUSTOMER_IDS = list(range(1, 21))
VENDOR_IDS   = list(range(21, 31))
RIDER_IDS    = list(range(31, 41))
ORDER_IDS    = list(range(1, 51))
PRODUCT_IDS  = list(range(1, 61))

# Fake UUID strings for text-based UUID columns
customer_uuids = [uid() for _ in range(20)]
rider_uuids    = [uid() for _ in range(10)]
admin_uuids    = [uid() for _ in range(3)]

# ── 1. admins ─────────────────────────────────────────────────────────────────
# Columns: userid(text), adminlevel(int), isverified(bool),
#          permissions(text), lastlogin(ts), department(text), created_at(ts)
admins = []
for i in range(3):
    admins.append({
        "userid":      admin_uuids[i],
        "adminlevel":  i + 1,
        "isverified":  "true",
        "permissions": ["all", "read_write", "read"][i],
        "lastlogin":   rdate(5),
        "department":  ["Operations", "Support", "Finance"][i],
        "created_at":  rdate(180),
    })

# ── 2. analytics ─────────────────────────────────────────────────────────────
# Columns: dashboardid(text), totalorders(int), revenue(float),
#          activeriders(int), lastlogin(ts), topsellingproducts(text), created_at(ts)
product_names = ["Biryani", "Burger", "Pizza", "Milk", "Soap", "Panadol"]
analytics = []
for _ in range(10):
    analytics.append({
        "dashboardid":        uid(),
        "totalorders":        random.randint(100, 5000),
        "revenue":            round(random.uniform(5000, 500000), 2),
        "activeriders":       random.randint(2, 15),
        "lastlogin":          rdate(2),
        "topsellingproducts": ", ".join(random.sample(product_names, 3)),
        "created_at":         rdate(30),
    })

# ── 3. audit_logs ─────────────────────────────────────────────────────────────
# Columns: logid(text), userid(text), sessiontoken(text),
#          action(text), module(text), timestamp(ts)
modules = ["Auth", "Orders", "Payments", "Products", "Riders", "Vendors"]
actions = ["LOGIN", "LOGOUT", "CREATE", "UPDATE", "DELETE", "VIEW"]
audit_logs = []
for _ in range(30):
    audit_logs.append({
        "logid":        uid(),
        "userid":       random.choice(customer_uuids + rider_uuids),
        "sessiontoken": uid(),
        "action":       random.choice(actions),
        "module":       random.choice(modules),
        "timestamp":    rdate(30),
    })

# ── 4. cart ───────────────────────────────────────────────────────────────────
# Columns: cartid(text), customerid(text), cartitems(text),
#          totalprice(float), updatedat(ts)
cart = []
for i, cuuid in enumerate(customer_uuids):
    p1 = random.choice(PRODUCT_IDS)
    p2 = random.choice(PRODUCT_IDS)
    cart.append({
        "cartid":     uid(),
        "customerid": cuuid,
        "cartitems":  f"product_{p1}, product_{p2}",
        "totalprice": round(random.uniform(200, 3000), 2),
        "updatedat":  rdate(3),
    })

# ── 5. cart_items ─────────────────────────────────────────────────────────────
# Columns: id(uuid), user_id(uuid), product_id(text), name(text),
#          price(int), quantity(int), image(text), created_at(ts)
item_names = ["Biryani", "Burger", "Pizza", "Milk", "Soap",
              "Panadol", "Shampoo", "Detergent", "Chicken", "Rice"]
cart_items = []
for _ in range(50):
    cart_items.append({
        "id":         uid(),
        "user_id":    random.choice(customer_uuids),
        "product_id": str(random.choice(PRODUCT_IDS)),
        "name":       random.choice(item_names),
        "price":      random.randint(50, 2000),
        "quantity":   random.randint(1, 5),
        "image":      "https://via.placeholder.com/200",
        "created_at": rdate(5),
    })

# ── 6. categories ─────────────────────────────────────────────────────────────
# Columns: name(text), description(text), created_at(ts)
cats = [
    ("Food",      "Hot meals, fast food, and local cuisine"),
    ("Grocery",   "Fresh produce, dairy, and household items"),
    ("Pharmacy",  "Medicines, supplements, and health products"),
    ("Thrift",    "Second-hand clothing and accessories"),
    ("Preloved",  "Gently used items at discounted prices"),
    ("Gifts",     "Gift boxes, flowers, and surprises"),
    ("Tailoring", "Custom stitching and alteration services"),
]
categories = [{"name": n, "description": d, "created_at": rdate(180)} for n, d in cats]

# ── 7. chat_messages ──────────────────────────────────────────────────────────
# Columns: room_id(bigint), sender_id(bigint), message(text),
#          image_url(text), is_read(bool), created_at(ts)
texts = [
    "Hi, is my order on the way?", "Yes, rider has picked it up.",
    "Approximately how long?", "About 15 minutes.", "Thank you!",
    "Can I change the delivery address?", "One item seems missing.",
    "Great service!", "Will order again soon.", "Please hurry!",
]
chat_messages = []
for _ in range(40):
    chat_messages.append({
        "room_id":   random.randint(1, 10),
        "sender_id": random.randint(1, 40),
        "message":   random.choice(texts),
        "image_url": "",
        "is_read":   random.choice(["true", "false"]),
        "created_at": rdate(10),
    })

# ── 8. chat_participants ──────────────────────────────────────────────────────
# Columns: room_id(bigint), user_id(bigint)   — NO id column
chat_participants = []
seen_cp = set()
for _ in range(40):
    room = random.randint(1, 10)
    user = random.randint(1, 40)
    if (room, user) not in seen_cp:
        seen_cp.add((room, user))
        chat_participants.append({"room_id": room, "user_id": user})

# ── 9. complaints ─────────────────────────────────────────────────────────────
# Columns: id(uuid), user_id(uuid), order_id(bigint),
#          type(text), description(text), status(text), created_at(ts)
comp_types = ["Late Delivery", "Wrong Item", "Missing Item", "Damaged Package", "Payment Issue"]
comp_descs = [
    "Rider arrived more than 30 minutes late.",
    "I received the wrong item in my order.",
    "One item from my order is missing.",
    "The package arrived damaged.",
    "Payment was deducted but order was not confirmed.",
]
complaints = []
for i in range(20):
    idx = i % len(comp_types)
    complaints.append({
        "id":          uid(),
        "user_id":     random.choice(customer_uuids),
        "order_id":    random.choice(ORDER_IDS),
        "type":        comp_types[idx],
        "description": comp_descs[idx],
        "status":      random.choice(["Open", "Under Review", "Resolved", "Closed"]),
        "created_at":  rdate(30),
    })

# ── 10. customer ──────────────────────────────────────────────────────────────
# Columns: user_id(bigint), name(text), phone(text), address(text), created_at(ts)
cust_names = [
    "Ayesha Khan", "Ali Hassan", "Sara Ahmed", "Bilal Raza", "Hina Malik",
    "Usman Sheikh", "Zara Siddiqui", "Hamza Javed", "Nadia Iqbal", "Farhan Butt",
    "Amna Chaudhry", "Arslan Nawaz", "Maham Tahir", "Sohaib Mirza", "Rabia Aslam",
    "Talha Qureshi", "Iqra Yousaf", "Danish Baig", "Mehwish Rao", "Waseem Zafar",
]
addresses = [
    "House 12, F-7/2, Islamabad",    "Plot 34, G-10 Markaz, Islamabad",
    "Flat 201, Gulberg Residencia",   "Sector I-8/3, Islamabad",
    "Bahria Town Phase 4, Rawalpindi","DHA Phase 2, Islamabad",
    "Model Town, Rawalpindi",          "PWD Housing Scheme, Islamabad",
    "F-10 Markaz, Islamabad",          "G-11/3, Islamabad",
    "Street 5, E-11, Islamabad",       "Blue Area, Islamabad",
    "I-9 Markaz, Islamabad",           "Saddar, Rawalpindi",
    "Jinnah Super, F-7, Islamabad",    "Melody Market, Islamabad",
    "Centaurus Mall Area, Islamabad",  "Packages Mall Area, Islamabad",
    "F-6/1, Islamabad",                "G-9/2, Islamabad",
]
customer_rows = []
for i, cid in enumerate(CUSTOMER_IDS):
    customer_rows.append({
        "user_id":    cid,
        "name":       cust_names[i],
        "phone":      f"+9230{random.randint(10000000, 99999999)}",
        "address":    addresses[i],
        "created_at": rdate(90),
    })

# ── 11. delivery_proof ────────────────────────────────────────────────────────
# Columns: proofid(text), orderid(text), riderid(text), photourl(text),
#          location(text), timestamp(ts), otpconfirmed(bool),
#          otp(text), is_verified(bool), verified_at(ts)
delivery_proof = []
for i in range(1, 26):  # first 25 orders delivered
    otp_val = f"{random.randint(100000, 999999)}"
    ts = rdate(15)
    delivery_proof.append({
        "proofid":      uid(),
        "orderid":      str(i),
        "riderid":      random.choice(rider_uuids),
        "photourl":     "https://via.placeholder.com/300",
        "location":     "Islamabad, Pakistan",
        "timestamp":    ts,
        "otpconfirmed": "true",
        "otp":          otp_val,
        "is_verified":  "true",
        "verified_at":  ts,
    })

# ── 12. favourite ─────────────────────────────────────────────────────────────
# Columns: user_id(bigint), product_id(bigint), created_at(ts)
favourite = []
seen_fav = set()
for _ in range(50):
    uid_val = random.choice(CUSTOMER_IDS)
    pid     = random.choice(PRODUCT_IDS)
    if (uid_val, pid) not in seen_fav:
        seen_fav.add((uid_val, pid))
        favourite.append({
            "user_id":    uid_val,
            "product_id": pid,
            "created_at": rdate(30),
        })

# ── 13. feedback ──────────────────────────────────────────────────────────────
# Columns: feedbackid(text), orderid(text), customerid(text), rating(int),
#          comment(text), targetid(text), targettype(text), created_at(ts)
fb_comments = [
    "Excellent service, very fast!", "Food was delicious and hot.",
    "Rider was polite and on time.", "Great experience overall.",
    "Will definitely order again!", "The packaging was perfect.",
    "Delivery was a bit late but food was good.", "Amazing! 5 stars.",
]
target_types = ["vendor", "rider", "product"]
feedback = []
for _ in range(30):
    feedback.append({
        "feedbackid": uid(),
        "orderid":    str(random.choice(ORDER_IDS)),
        "customerid": random.choice(customer_uuids),
        "rating":     random.randint(3, 5),
        "comment":    random.choice(fb_comments),
        "targetid":   str(random.choice(PRODUCT_IDS)),
        "targettype": random.choice(target_types),
        "created_at": rdate(20),
    })

# ── 14. gifts ─────────────────────────────────────────────────────────────────
# Columns: id(uuid), sender_id(uuid), recipient_name(text), recipient_address(text),
#          message(text), occasion(text), gift_item_id(text), gift_item_name(text),
#          amount(int), status(text), created_at(ts)
occasions   = ["Birthday", "Eid", "Anniversary", "Recovery", "Congratulations"]
gift_items  = ["Chocolate Box", "Flower Bouquet", "Gift Hamper", "Cake", "Perfume"]
gift_msgs   = ["Happy Birthday!", "Eid Mubarak!", "Congratulations!", "Get well soon!", "Thank you!"]
gift_addrs  = ["F-7/2 Islamabad", "G-10 Islamabad", "DHA Rawalpindi", "Bahria Town", "I-8 Islamabad"]
gifts = []
for _ in range(15):
    item = random.choice(gift_items)
    gifts.append({
        "id":               uid(),
        "sender_id":        random.choice(customer_uuids),
        "recipient_name":   random.choice(["Ali Raza", "Sara Bano", "Ahmed Khan", "Fatima Noor"]),
        "recipient_address": random.choice(gift_addrs),
        "message":          random.choice(gift_msgs),
        "occasion":         random.choice(occasions),
        "gift_item_id":     str(random.choice(PRODUCT_IDS)),
        "gift_item_name":   item,
        "amount":           random.randint(500, 5000),
        "status":           random.choice(["pending", "delivered", "cancelled"]),
        "created_at":       rdate(30),
    })

# ── 15. payment ───────────────────────────────────────────────────────────────
# Columns: order_id(bigint), amount(numeric), method(text),
#          status(text), created_at(ts)
payment = []
for oid in ORDER_IDS:
    payment.append({
        "order_id":   oid,
        "amount":     random.randint(300, 5000),
        "method":     random.choice(["COD", "JazzCash", "EasyPaisa", "Card"]),
        "status":     random.choice(["Pending", "Completed", "Completed", "Completed"]),
        "created_at": rdate(30),
    })

# ── 16. review ────────────────────────────────────────────────────────────────
# Columns: product_id(bigint), user_id(bigint), rating(int),
#          comment(text), created_at(ts)
rev_comments = [
    "Highly recommended! Fresh and tasty.", "Good quality, will order again.",
    "Fast delivery and great product.",    "Excellent value for money.",
    "Very satisfied with this purchase.",  "Product matches the description.",
    "Could be better but decent quality.", "Outstanding! Exceeded expectations.",
]
review = []
seen_rev = set()
for _ in range(60):
    pid = random.choice(PRODUCT_IDS)
    cid = random.choice(CUSTOMER_IDS)
    if (pid, cid) not in seen_rev:
        seen_rev.add((pid, cid))
        review.append({
            "product_id": pid,
            "user_id":    cid,
            "rating":     random.randint(3, 5),
            "comment":    random.choice(rev_comments),
            "created_at": rdate(30),
        })

# ── 17. customers ─────────────────────────────────────────────────────────────
# Columns: user_id(bigint), name(text), phone(text), city(text),
#          address(text), order_count(int), created_at(ts)
cities = ["Islamabad", "Rawalpindi", "Lahore", "Karachi", "Peshawar"]
customers_rows = []
for i, cid in enumerate(CUSTOMER_IDS):
    customers_rows.append({
        "user_id":     cid,
        "name":        cust_names[i],
        "phone":       f"+9230{random.randint(10000000, 99999999)}",
        "city":        random.choice(cities),
        "address":     addresses[i],
        "order_count": random.randint(1, 20),
        "created_at":  rdate(90),
    })

# ── 18. favorites ─────────────────────────────────────────────────────────────
# Columns: user_id(uuid), favorite_user_id(uuid), type(text), created_at(ts)
# This is a user-to-user follow/favorite system
fav_types = ["vendor", "rider"]
favorites = []
seen_fav2 = set()
all_uuids = customer_uuids + rider_uuids
for _ in range(30):
    u  = random.choice(customer_uuids)
    fu = random.choice(all_uuids)
    if u != fu and (u, fu) not in seen_fav2:
        seen_fav2.add((u, fu))
        favorites.append({
            "user_id":          u,
            "favorite_user_id": fu,
            "type":             random.choice(fav_types),
            "created_at":       rdate(30),
        })

# ── 19. payments ──────────────────────────────────────────────────────────────
# Columns: paymentid(text), orderid(text), customerid(text), method(text),
#          status(text), amount(float), invoiceurl(text), paidat(ts)
payments = []
for oid in ORDER_IDS:
    ts = rdate(30)
    payments.append({
        "paymentid":  uid(),
        "orderid":    str(oid),
        "customerid": random.choice(customer_uuids),
        "method":     random.choice(["COD", "JazzCash", "EasyPaisa", "Card"]),
        "status":     random.choice(["Pending", "Completed", "Completed", "Completed"]),
        "amount":     round(random.uniform(300, 5000), 2),
        "invoiceurl": f"https://invoices.tezrider.com/inv_{oid}.pdf",
        "paidat":     ts,
    })

# ── Write all CSVs ────────────────────────────────────────────────────────────
print("\nGenerating CSVs in ./mock_data_extra_compatible/")
print("=" * 55)
write_csv("admins",            admins)
write_csv("analytics",         analytics)
write_csv("audit_logs",        audit_logs)
write_csv("cart",              cart)
write_csv("cart_items",        cart_items)
write_csv("categories",        categories)
write_csv("chat_messages",     chat_messages)
write_csv("chat_participants", chat_participants)
write_csv("complaints",        complaints)
write_csv("customer",          customer_rows)
write_csv("customers",         customers_rows)
write_csv("delivery_proof",    delivery_proof)
write_csv("favorites",         favorites)
write_csv("favourite",         favourite)
write_csv("feedback",          feedback)
write_csv("gifts",             gifts)
write_csv("payment",           payment)
write_csv("payments",          payments)
write_csv("review",            review)

print("\n" + "=" * 55)
print("Done! 19 CSV files ready in mock_data_extra_compatible/")
print()
print("IMPORT ORDER:")
print("  1. Run create_missing_tables.sql  (creates customers/customer/favourite/payment/review)")
print("  2. Run otp_delivery_setup.sql     (adds delivery_otp to orders)")
print("  3. Import: categories -> admins -> analytics -> audit_logs")
print("             -> cart -> cart_items -> customer -> customers -> favourite")
print("             -> payment -> payments -> review -> feedback -> gifts")
print("             -> favorites -> complaints -> delivery_proof")
print("             -> chat_participants -> chat_messages")
