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

# Kathmandu Valley only, for now — the app's initial service area.
CITIES: list[str] = [
    "Kathmandu",
    "Lalitpur",
    "Bhaktapur",
    "Kirtipur",
]

# Which municipalities show up depends on the selected city.
CITY_MUNICIPALITIES: dict[str, list[str]] = {
    "Kathmandu": [
        "Kathmandu Metropolitan City",
        "Chandragiri Municipality",
        "Tokha Municipality",
        "Budhanilkantha Municipality",
        "Tarakeshwor Municipality",
        "Gokarneshwor Municipality",
        "Kageshwori Manohara Municipality",
        "Nagarjun Municipality",
        "Dakshinkali Municipality",
    ],
    "Lalitpur": [
        "Lalitpur Metropolitan City",
        "Godawari Municipality",
        "Mahalaxmi Municipality",
    ],
    "Bhaktapur": [
        "Bhaktapur Municipality",
        "Madhyapur Thimi Municipality",
        "Suryabinayak Municipality",
        "Changunarayan Municipality",
    ],
    "Kirtipur": [
        "Kirtipur Municipality",
    ],
}

EXPERIENCE_RANGES: list[str] = [
    "Less than 1 year",
    "1-3 years",
    "3-5 years",
    "5-10 years",
    "10+ years",
]

MARITAL_STATUS_OPTIONS: list[str] = [
    "single",
    "married",
]