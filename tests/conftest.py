import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

import pytest
from app import app as flask_app, db, Product, Customer


@pytest.fixture
def app():
    flask_app.config["TESTING"] = True
    flask_app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///:memory:"
    with flask_app.app_context():
        db.create_all()
        _seed()
        yield flask_app
        db.session.remove()
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


def _seed():
    db.session.add_all([
        Product(name="Test Phone", category="electronics", emoji="📱",
                price=499, old_price=599, badge="sale", rating=4.7, reviews_count=100, stock=20),
        Product(name="Test Shirt", category="fashion", emoji="👕",
                price=29, old_price=49, badge="new", rating=4.3, reviews_count=50, stock=100),
        Product(name="Test Shoes", category="sports", emoji="👟",
                price=89, old_price=119, badge="hot", rating=4.5, reviews_count=80, stock=60),
    ])
    db.session.commit()
