import json


# ── Health ──────────────────────────────────────────────────────────────────

def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"
    assert r.get_json()["service"] == "shopwave"


# ── Products ────────────────────────────────────────────────────────────────

def test_get_all_products(client):
    r = client.get("/api/products")
    assert r.status_code == 200
    data = r.get_json()
    assert "products" in data
    assert len(data["products"]) == 3


def test_get_products_by_category(client):
    r = client.get("/api/products?category=electronics")
    assert r.status_code == 200
    products = r.get_json()["products"]
    assert len(products) == 1
    assert products[0]["category"] == "electronics"


def test_get_products_no_match(client):
    r = client.get("/api/products?category=beauty")
    assert r.status_code == 200
    assert len(r.get_json()["products"]) == 0


def test_get_single_product(client):
    r = client.get("/api/products/1")
    assert r.status_code == 200
    p = r.get_json()
    assert p["name"] == "Test Phone"
    assert p["price"] == 499.0
    assert p["discount"] == "-17%"


def test_get_product_not_found(client):
    r = client.get("/api/products/9999")
    assert r.status_code == 404


def test_product_has_discount(client):
    r = client.get("/api/products/1")
    p = r.get_json()
    assert p["discount"] is not None
    assert p["old_price"] == 599.0


# ── Customers ───────────────────────────────────────────────────────────────

def test_register_customer(client):
    r = client.post("/api/customers/register", json={
        "name": "Alice", "email": "alice@test.com", "password": "secret123"
    })
    assert r.status_code == 201
    assert "id" in r.get_json()


def test_register_missing_fields(client):
    r = client.post("/api/customers/register", json={"name": "Bob"})
    assert r.status_code == 400


def test_register_duplicate_email(client):
    payload = {"name": "Carol", "email": "carol@test.com", "password": "pass"}
    client.post("/api/customers/register", json=payload)
    r = client.post("/api/customers/register", json=payload)
    assert r.status_code == 409


def test_login_success(client):
    client.post("/api/customers/register", json={
        "name": "Dave", "email": "dave@test.com", "password": "mypass"
    })
    r = client.post("/api/customers/login", json={
        "email": "dave@test.com", "password": "mypass"
    })
    assert r.status_code == 200
    assert r.get_json()["name"] == "Dave"


def test_login_wrong_password(client):
    client.post("/api/customers/register", json={
        "name": "Eve", "email": "eve@test.com", "password": "correct"
    })
    r = client.post("/api/customers/login", json={
        "email": "eve@test.com", "password": "wrong"
    })
    assert r.status_code == 401


def test_login_unknown_email(client):
    r = client.post("/api/customers/login", json={
        "email": "ghost@test.com", "password": "pass"
    })
    assert r.status_code == 401


# ── Orders ──────────────────────────────────────────────────────────────────

def test_place_order(client):
    r = client.post("/api/orders", json={
        "customer_name": "Frank",
        "customer_email": "frank@test.com",
        "items": [{"product_id": 1, "quantity": 2}],
    })
    assert r.status_code == 201
    data = r.get_json()
    assert "order_id" in data
    assert data["total"] == 998.0


def test_place_order_multiple_items(client):
    r = client.post("/api/orders", json={
        "customer_name": "Grace",
        "customer_email": "grace@test.com",
        "items": [
            {"product_id": 1, "quantity": 1},
            {"product_id": 2, "quantity": 3},
        ],
    })
    assert r.status_code == 201
    assert r.get_json()["total"] == 499 + 29 * 3


def test_place_order_empty_items(client):
    r = client.post("/api/orders", json={
        "customer_name": "Hank", "customer_email": "hank@test.com", "items": []
    })
    assert r.status_code == 400


def test_place_order_missing_customer(client):
    r = client.post("/api/orders", json={
        "items": [{"product_id": 1, "quantity": 1}]
    })
    assert r.status_code == 400


def test_place_order_invalid_product(client):
    r = client.post("/api/orders", json={
        "customer_name": "Ivan", "customer_email": "ivan@test.com",
        "items": [{"product_id": 9999, "quantity": 1}],
    })
    assert r.status_code == 404


def test_get_orders(client):
    client.post("/api/orders", json={
        "customer_name": "Jane", "customer_email": "jane@test.com",
        "items": [{"product_id": 1, "quantity": 1}],
    })
    r = client.get("/api/orders")
    assert r.status_code == 200
    assert len(r.get_json()["orders"]) == 1


# ── Frontend ─────────────────────────────────────────────────────────────────

def test_index_page(client):
    r = client.get("/")
    assert r.status_code == 200
    assert b"ShopWave" in r.data
