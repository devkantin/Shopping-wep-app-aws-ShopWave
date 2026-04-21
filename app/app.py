import os
from flask import Flask, jsonify, request, render_template
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime

app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY", "dev-secret")
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

if os.environ.get("TESTING") == "1" or app.config.get("TESTING"):
    app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///:memory:"
else:
    DB_USER = os.environ.get("DB_USER", "admin")
    DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
    DB_HOST = os.environ.get("DB_HOST", "localhost")
    DB_NAME = os.environ.get("DB_NAME", "shopwave_db")
    app.config["SQLALCHEMY_DATABASE_URI"] = (
        f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}"
    )

db = SQLAlchemy(app)


# ── Models ────────────────────────────────────────────────────────────────────

class Product(db.Model):
    __tablename__ = "products"
    id            = db.Column(db.Integer, primary_key=True)
    name          = db.Column(db.String(100), nullable=False)
    category      = db.Column(db.String(50), nullable=False)
    emoji         = db.Column(db.String(10), default="🛍️")
    price         = db.Column(db.Numeric(10, 2), nullable=False)
    old_price     = db.Column(db.Numeric(10, 2))
    badge         = db.Column(db.String(20))
    rating        = db.Column(db.Numeric(3, 1), default=4.5)
    reviews_count = db.Column(db.Integer, default=0)
    stock         = db.Column(db.Integer, default=100)
    description   = db.Column(db.Text)

    def to_dict(self):
        discount = None
        if self.old_price and float(self.old_price) > 0:
            pct = round((1 - float(self.price) / float(self.old_price)) * 100)
            discount = f"-{pct}%"
        return {
            "id":            self.id,
            "name":          self.name,
            "category":      self.category,
            "emoji":         self.emoji,
            "price":         float(self.price),
            "old_price":     float(self.old_price) if self.old_price else None,
            "badge":         self.badge,
            "rating":        float(self.rating) if self.rating else None,
            "reviews_count": self.reviews_count,
            "stock":         self.stock,
            "discount":      discount,
        }


class Customer(db.Model):
    __tablename__ = "customers"
    id            = db.Column(db.Integer, primary_key=True)
    name          = db.Column(db.String(100), nullable=False)
    email         = db.Column(db.String(150), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at    = db.Column(db.DateTime, default=datetime.utcnow)


class Order(db.Model):
    __tablename__ = "orders"
    id             = db.Column(db.Integer, primary_key=True)
    customer_name  = db.Column(db.String(100), nullable=False)
    customer_email = db.Column(db.String(150), nullable=False)
    total          = db.Column(db.Numeric(10, 2), nullable=False)
    status         = db.Column(db.String(20), default="pending")
    created_at     = db.Column(db.DateTime, default=datetime.utcnow)
    items          = db.relationship("OrderItem", backref="order", lazy=True)


class OrderItem(db.Model):
    __tablename__ = "order_items"
    id           = db.Column(db.Integer, primary_key=True)
    order_id     = db.Column(db.Integer, db.ForeignKey("orders.id"), nullable=False)
    product_id   = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    product_name = db.Column(db.String(100))
    quantity     = db.Column(db.Integer, nullable=False)
    unit_price   = db.Column(db.Numeric(10, 2), nullable=False)


# ── Seed ──────────────────────────────────────────────────────────────────────

def seed_products():
    if Product.query.count() > 0:
        return
    items = [
        Product(name="iPhone 16 Pro",      category="electronics", emoji="📱", price=999,  old_price=1199, badge="sale", rating=4.8, reviews_count=3240, stock=50),
        Product(name="Nike Air Force 1",   category="fashion",     emoji="👟", price=129,  old_price=159,  badge="hot",  rating=4.7, reviews_count=8900, stock=200),
        Product(name="MacBook Air M3",     category="electronics", emoji="💻", price=1299, old_price=1499, badge="new",  rating=4.9, reviews_count=1820, stock=30),
        Product(name="Leather Handbag",    category="fashion",     emoji="👜", price=89,   old_price=129,  badge="sale", rating=4.6, reviews_count=2140, stock=75),
        Product(name="Smart Watch Ultra",  category="electronics", emoji="⌚", price=349,  old_price=449,  badge="hot",  rating=4.8, reviews_count=5670, stock=80),
        Product(name="Yoga Mat Pro",       category="sports",      emoji="🧘", price=49,   old_price=69,   badge="sale", rating=4.5, reviews_count=1230, stock=150),
        Product(name="Wireless Earbuds",   category="electronics", emoji="🎧", price=179,  old_price=249,  badge="new",  rating=4.7, reviews_count=4560, stock=100),
        Product(name="Floral Dress",       category="fashion",     emoji="👗", price=59,   old_price=89,   badge="sale", rating=4.6, reviews_count=3100, stock=60),
        Product(name="Moisturizer SPF50",  category="beauty",      emoji="🧴", price=34,   old_price=49,   badge="new",  rating=4.4, reviews_count=980,  stock=200),
        Product(name="Running Shoes",      category="sports",      emoji="👟", price=119,  old_price=149,  badge="hot",  rating=4.7, reviews_count=2200, stock=90),
        Product(name="Smart TV 55\"",      category="electronics", emoji="📺", price=599,  old_price=799,  badge="sale", rating=4.6, reviews_count=1450, stock=25),
        Product(name="Denim Jacket",       category="fashion",     emoji="🧥", price=79,   old_price=109,  badge="hot",  rating=4.5, reviews_count=1800, stock=55),
    ]
    db.session.add_all(items)
    db.session.commit()


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/products")
def get_products():
    category = request.args.get("category")
    query = Product.query
    if category and category != "all":
        query = query.filter_by(category=category)
    return jsonify({"products": [p.to_dict() for p in query.all()]})


@app.route("/api/products/<int:product_id>")
def get_product(product_id):
    p = Product.query.get_or_404(product_id)
    return jsonify(p.to_dict())


@app.route("/api/customers/register", methods=["POST"])
def register():
    data = request.get_json() or {}
    if not all(k in data for k in ("name", "email", "password")):
        return jsonify({"error": "name, email and password are required"}), 400
    if Customer.query.filter_by(email=data["email"]).first():
        return jsonify({"error": "Email already registered"}), 409
    customer = Customer(
        name=data["name"],
        email=data["email"],
        password_hash=generate_password_hash(data["password"]),
    )
    db.session.add(customer)
    db.session.commit()
    return jsonify({"message": "Registered successfully", "id": customer.id}), 201


@app.route("/api/customers/login", methods=["POST"])
def login():
    data = request.get_json() or {}
    customer = Customer.query.filter_by(email=data.get("email", "")).first()
    if not customer or not check_password_hash(customer.password_hash, data.get("password", "")):
        return jsonify({"error": "Invalid credentials"}), 401
    return jsonify({"message": "Login successful", "id": customer.id, "name": customer.name})


@app.route("/api/orders", methods=["POST"])
def place_order():
    data = request.get_json() or {}
    items = data.get("items", [])
    if not items:
        return jsonify({"error": "No items in order"}), 400
    if not data.get("customer_name") or not data.get("customer_email"):
        return jsonify({"error": "customer_name and customer_email are required"}), 400

    total = 0.0
    order_items = []
    for item in items:
        product = Product.query.get(item.get("product_id"))
        if not product:
            return jsonify({"error": f"Product {item.get('product_id')} not found"}), 404
        qty = int(item.get("quantity", 1))
        total += float(product.price) * qty
        order_items.append(
            OrderItem(product_id=product.id, product_name=product.name,
                      quantity=qty, unit_price=product.price)
        )

    order = Order(customer_name=data["customer_name"],
                  customer_email=data["customer_email"], total=round(total, 2))
    db.session.add(order)
    db.session.flush()
    for oi in order_items:
        oi.order_id = order.id
        db.session.add(oi)
    db.session.commit()
    return jsonify({"message": "Order placed!", "order_id": order.id, "total": round(total, 2)}), 201


@app.route("/api/orders", methods=["GET"])
def get_orders():
    orders = Order.query.order_by(Order.created_at.desc()).limit(50).all()
    return jsonify({"orders": [
        {"id": o.id, "customer_name": o.customer_name, "customer_email": o.customer_email,
         "total": float(o.total), "status": o.status,
         "items": [{"product_name": i.product_name, "quantity": i.quantity,
                    "unit_price": float(i.unit_price)} for i in o.items]}
        for o in orders
    ]})


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "shopwave"})


if __name__ == "__main__":
    with app.app_context():
        db.create_all()
        seed_products()
    app.run(host="0.0.0.0", port=5000)
