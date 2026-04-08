from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from .crew import build_shop_crew

app = FastAPI(title="CrewAI Shop Builder", version="1.0.0")


class ShopRequest(BaseModel):
    shop_name: str = "K8Exo Merch"
    description: str


class ShopResponse(BaseModel):
    lovable_prompt: str
    backend_code: str
    tests: str
    security_report: str


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/build-shop", response_model=ShopResponse)
async def build_shop(request: ShopRequest):
    try:
        crew = build_shop_crew(request.shop_name, request.description)
        result = crew.kickoff()

        outputs = result.tasks_output
        return ShopResponse(
            lovable_prompt=outputs[0].raw if len(outputs) > 0 else "",
            backend_code=outputs[1].raw if len(outputs) > 1 else "",
            tests=outputs[2].raw if len(outputs) > 2 else "",
            security_report=outputs[3].raw if len(outputs) > 3 else "",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
