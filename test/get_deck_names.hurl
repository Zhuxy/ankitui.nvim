# Get deck names
POST http://localhost:8765
Content-Type: application/json
{
    "action": "deckNames",
    "version": 6
}

HTTP 200
[Asserts]
jsonpath "$.result" isCollection
