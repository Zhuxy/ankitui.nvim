# Find notes in a specific deck
POST http://localhost:8765
Content-Type: application/json
{
    "action": "findNotes",
    "version": 6,
    "params": {
        "query": "deck:Default"
    }
}

HTTP 200
[Asserts]
jsonpath "$.result" isCollection
