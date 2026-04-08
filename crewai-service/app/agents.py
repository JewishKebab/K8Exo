import os
from crewai import Agent, LLM

OLLAMA_BASE_URL = os.getenv("OLLAMA_URL", "http://ollama.platform.svc.cluster.local:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "ollama/llama3.1:8b")


def get_llm() -> LLM:
    return LLM(
        model=OLLAMA_MODEL,
        base_url=OLLAMA_BASE_URL,
        temperature=0.7,
    )


def prompt_generator_agent() -> Agent:
    return Agent(
        role="UI/UX Prompt Engineer",
        goal="Generate detailed, creative prompts for AI-powered frontend builders like Lovable.dev",
        backstory=(
            "You are an expert at crafting precise, structured prompts that result in "
            "beautiful, functional e-commerce UIs. You understand design systems, "
            "component libraries, and what makes a great shopping experience."
        ),
        llm=get_llm(),
        verbose=True,
    )


def backend_developer_agent() -> Agent:
    return Agent(
        role="Senior Python Backend Developer",
        goal="Write clean, production-ready FastAPI backends for e-commerce applications",
        backstory=(
            "You have 10 years of Python experience, specializing in FastAPI REST APIs. "
            "You write clean, well-structured code with proper separation of concerns, "
            "Pydantic validation, and SQLAlchemy ORM. You always include CORS for frontend integration."
        ),
        llm=get_llm(),
        verbose=True,
    )


def qa_agent() -> Agent:
    return Agent(
        role="QA Engineer",
        goal="Write comprehensive pytest test suites that cover happy paths and edge cases",
        backstory=(
            "You practice TDD and write tests that actually catch bugs. "
            "You know FastAPI's TestClient well, write proper fixtures, "
            "and always test both success and failure scenarios."
        ),
        llm=get_llm(),
        verbose=True,
    )


def security_agent() -> Agent:
    return Agent(
        role="Application Security Engineer",
        goal="Identify security vulnerabilities in Python web applications and provide actionable fixes",
        backstory=(
            "You are an OWASP expert specializing in API security. "
            "You review code for injection attacks, auth gaps, data exposure, "
            "and misconfigurations. You provide clear severity ratings and concrete remediation steps."
        ),
        llm=get_llm(),
        verbose=True,
    )
