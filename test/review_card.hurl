# Review a card (example: set ease factor for a card - replace with actual card ID)
# You'll need to run 'findCards' first and use a card ID from the result.
POST http://localhost:8765
Content-Type: application/json
{
    "action": "answerCards",
    "version": 6,
    "params": {
        "answers": [
            {
                "cardId": 1688234567892, # Replace with an actual card ID
                "ease": 3 # 1=Again, 2=Hard, 3=Good, 4=Easy
            }
        ]
    }
}

HTTP 200
[Asserts]
jsonpath "$.result" isCollection
