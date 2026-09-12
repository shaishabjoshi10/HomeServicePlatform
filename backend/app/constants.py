SERVICE_CATEGORIES: list[str] = [
    "Plumbing",
    "Electrical",
    "Cleaning",
    "Carpentry",
    "Painting",
    "Appliance Repair",
    "Pest Control",
    "Gardening",
    "Moving & Packing",
]

# Kathmandu Valley only, for now — the app's initial service area. Provider
# verification no longer collects a free-choice city/municipality/address —
# every provider is fixed to this single default city.
DEFAULT_CITY: str = "Kathmandu"

EXPERIENCE_RANGES: list[str] = [
    "Less than 1 year",
    "1-3 years",
    "3-5 years",
    "5-10 years",
    "10+ years",
]