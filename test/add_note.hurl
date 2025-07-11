# Add a note
POST http://localhost:8765
Content-Type: application/json
{
    "action": "addNote",
    "version": 6,
    "params": {
        "note": {
            "deckName": "Default",
            "modelName": "Basic",
            "fields": {
                "Front": "Hurl Test Front",
                "Back": "Hurl Test Back"
            },
            "tags": ["hurl_test"]
        }
    }
}

HTTP 200
[Asserts]
jsonpath "$.result" isInteger
