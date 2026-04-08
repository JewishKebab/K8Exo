from crewai import Crew, Process
from .agents import (
    prompt_generator_agent,
    backend_developer_agent,
    qa_agent,
    security_agent,
)
from .tasks import lovable_prompt_task, backend_task, tests_task, security_task


def build_shop_crew(shop_name: str, shop_description: str) -> Crew:
    # Agents
    prompt_agent = prompt_generator_agent()
    dev_agent = backend_developer_agent()
    qa = qa_agent()
    sec = security_agent()

    # Tasks — sequential: prompt and backend run first, then tests/security use backend output
    t_prompt = lovable_prompt_task(prompt_agent, shop_name, shop_description)
    t_backend = backend_task(dev_agent, shop_name, shop_description)
    t_tests = tests_task(qa, t_backend)
    t_security = security_task(sec, t_backend)

    return Crew(
        agents=[prompt_agent, dev_agent, qa, sec],
        tasks=[t_prompt, t_backend, t_tests, t_security],
        process=Process.sequential,
        verbose=True,
    )
