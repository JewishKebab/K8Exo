from crewai import Task
from crewai import Agent


def lovable_prompt_task(agent: Agent, shop_name: str, shop_description: str) -> Task:
    return Task(
        description=f"""
        Generate a detailed Lovable.dev prompt for a merch shop.

        Shop name: {shop_name}
        Description: {shop_description}

        The prompt must specify:
        - Overall design aesthetic and color scheme (be specific: hex colors, font families)
        - Page structure: homepage, product catalog, product detail, cart, checkout, order confirmation
        - Component specs: navbar with cart icon + item count, product cards with hover effects,
          size/variant selectors, quantity picker, filter sidebar
        - Mobile-first responsive layout
        - Any animations or micro-interactions

        Output ONLY the Lovable.dev prompt text. No preamble, no explanation.
        """,
        expected_output=(
            "A detailed, structured prompt ready to paste directly into Lovable.dev "
            "that will generate a complete merch shop frontend."
        ),
        agent=agent,
    )


def backend_task(agent: Agent, shop_name: str, shop_description: str) -> Task:
    return Task(
        description=f"""
        Write a complete FastAPI backend for this merch shop:

        Shop name: {shop_name}
        Description: {shop_description}

        Requirements:
        - Products: id, name, description, price, image_url, stock, category, variants (sizes/colors as JSON)
        - Cart: session-based, add/remove/update quantity, get cart total
        - Orders: create order from cart, list orders by session
        - SQLite + SQLAlchemy ORM (sync, no async ORM)
        - Pydantic v2 models for all request/response schemas
        - CORS enabled for all origins (frontend will be on a different domain)
        - Auto-populate 6 sample products on startup if DB is empty

        Output a single complete main.py file. Include all imports. Must be runnable with:
        uvicorn main:app --reload
        """,
        expected_output="A single complete main.py FastAPI application file, no markdown fences.",
        agent=agent,
    )


def tests_task(agent: Agent, backend_task_ref: Task) -> Task:
    return Task(
        description="""
        Write a pytest test suite for the FastAPI backend from the previous task.

        Include:
        - Fixtures: test client, fresh in-memory SQLite DB per test
        - Product tests: list all, get by id, get non-existent (404)
        - Cart tests: add item, add same item again (quantity increases), remove item, update quantity, get empty cart
        - Order tests: create order from cart, create order from empty cart (should fail), list orders
        - Validation tests: invalid price, negative quantity, missing required fields

        Use FastAPI TestClient (not async). Output a single test_main.py file.
        """,
        expected_output="A complete test_main.py pytest file with all fixtures and test cases.",
        agent=agent,
        context=[backend_task_ref],
    )


def security_task(agent: Agent, backend_task_ref: Task) -> Task:
    return Task(
        description="""
        Review the FastAPI backend code from the previous task for security vulnerabilities.

        Check for:
        1. OWASP Top 10 (injection, broken auth, sensitive data exposure, etc.)
        2. SQL injection via raw queries or ORM misuse
        3. Missing authentication/authorization on admin-like endpoints
        4. CORS misconfiguration (all origins allowed — flag this)
        5. Input validation gaps
        6. Sensitive data in responses (e.g., internal IDs, stack traces)
        7. Missing rate limiting
        8. Insecure session handling (session IDs in URLs, predictable IDs)

        Output a structured report:

        ## Critical
        - [issue] — [why it's dangerous] — [fix]

        ## High
        - ...

        ## Medium
        - ...

        ## Recommendations
        - ...
        """,
        expected_output="A structured security report with findings by severity and actionable fixes.",
        agent=agent,
        context=[backend_task_ref],
    )
