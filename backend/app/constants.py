import enum
from typing import NamedTuple

SERVICE_CATEGORIES: list[str] = [
    "Electrical",
    "Cleaning",
    "Plumbing",
    "Painting",
    "Appliance Repair",
    "Carpentry",
    "Laundry",
    "Pest Control",
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

# ── Service pricing ───────────────────────────────────────────────────────
#
# Prices are per *job*, not per category: a category is just a grouping, and
# "Cleaning" on its own has no price. Every bookable job below carries its
# own price in NPR.

CURRENCY_SYMBOL: str = "Rs."


class PriceType(str, enum.Enum):
    """
    How a job's price should be read.

    fixed         — the quoted amount is the whole price for a standard job
                    of this kind (e.g. installing one fan).
    starting_from — the job's real cost depends on scope (area, severity,
                    materials), so the quoted amount is the minimum and the
                    final bill is agreed after the professional inspects it.
    """

    fixed = "fixed"
    starting_from = "starting_from"


def format_price_label(price: float | None, price_type: str | None) -> str | None:
    """
    Display string for a price, e.g. "Rs. 500" or "From Rs. 2,500".

    Takes the raw values (rather than a ServiceJob) so it works equally for
    a live catalogue entry and for the price snapshotted onto a booking row,
    which may no longer match the current catalogue.
    """
    if price is None:
        return None
    amount = f"{CURRENCY_SYMBOL} {float(price):,.0f}"
    if price_type == PriceType.starting_from.value:
        return f"From {amount}"
    return amount


class ServiceJob(NamedTuple):
    """One specific, bookable job under a service category."""

    name: str
    description: str
    price: int  # NPR
    price_type: PriceType = PriceType.fixed

    @property
    def price_label(self) -> str:
        # price is never None on a catalogue entry, so this is never None.
        return format_price_label(self.price, self.price_type.value)


# The specific jobs a customer picks between after tapping a category, with
# the price of each. This is the single source of truth for prices: the app
# only displays what it reads from here (GET /api/services/catalog), and a
# booking's price is looked up here server-side rather than trusted from the
# client — see routers/bookings.py.
#
# Keys must match SERVICE_CATEGORIES exactly.
SERVICE_JOBS: dict[str, list[ServiceJob]] = {
    "Cleaning": [
        ServiceJob(
            "Room Cleaning",
            "Sweeping, mopping, dusting, and tidying for a single room.",
            500,
        ),
        ServiceJob(
            "Deep House Cleaning",
            "A thorough top-to-bottom clean covering floors, windows, kitchen surfaces, and bathrooms — ideal before a festival, move-in, or move-out.",
            2500,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Bathroom & Kitchen Cleaning",
            "Focused scrubbing and sanitizing of tiles, sinks, and stovetops to cut through built-up grease and grime.",
            1200,
        ),
        ServiceJob(
            "Sofa & Carpet Cleaning",
            "Steam or shampoo cleaning for sofas, carpets, and rugs to lift dust, stains, and odours.",
            1500,
            PriceType.starting_from,
        ),
    ],
    "Plumbing": [
        ServiceJob(
            "Leak & Pipe Repair",
            "Fixing leaking taps, pipes, and joints to stop water wastage and prevent damage to walls and floors.",
            700,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Tap & Fixture Installation",
            "Installing or replacing taps, showers, and wash-basin fittings.",
            600,
        ),
        ServiceJob(
            "Water Tank Cleaning",
            "Draining, scrubbing, and sanitizing overhead or underground water tanks.",
            1500,
            PriceType.starting_from,
        ),
    ],
    "Electrical": [
        ServiceJob(
            "Fan Installation",
            "Mounting and wiring a ceiling or wall fan, including testing the regulator.",
            600,
        ),
        ServiceJob(
            "Switchboard & Socket Repair",
            "Fixing faulty switches, sockets, and switchboards, including sparking or tripping issues.",
            500,
        ),
        ServiceJob(
            "Light Fitting Installation",
            "Installing or repairing tube lights, panel lights, and other light fixtures.",
            450,
        ),
        ServiceJob(
            "Wiring & Rewiring",
            "Inspecting and replacing old or unsafe household wiring.",
            1500,
            PriceType.starting_from,
        ),
    ],
    "Carpentry": [
        ServiceJob(
            "Furniture Repair",
            "Fixing broken chairs, tables, cupboards, and other wooden furniture.",
            800,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Door & Window Fitting",
            "Repairing or installing doors, windows, hinges, and locks that stick or don't close properly.",
            1000,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Custom Furniture Assembly",
            "Assembling flat-pack or made-to-order furniture at your home.",
            1200,
        ),
    ],
    "Painting": [
        ServiceJob(
            "Interior Wall Painting",
            "Full or touch-up painting for bedrooms, living rooms, and ceilings.",
            3000,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Exterior Wall Painting",
            "Weatherproof painting for outside walls and boundary walls.",
            5000,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Waterproofing & Wall Repair",
            "Treating damp patches, cracks, and seepage before repainting.",
            2500,
            PriceType.starting_from,
        ),
    ],
    "Appliance Repair": [
        ServiceJob(
            "Washing Machine Repair",
            "Diagnosing and fixing drainage, spinning, or power issues.",
            800,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Refrigerator Repair",
            "Fixing cooling problems, unusual noise, or leaks.",
            900,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Microwave & Oven Repair",
            "Repairing heating and control issues on microwaves and ovens.",
            700,
            PriceType.starting_from,
        ),
    ],
    "Laundry": [
        ServiceJob(
            "Wash & Fold",
            "Everyday clothes washed, dried, and neatly folded, ready to put away.",
            300,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Dry Cleaning",
            "Professional cleaning for suits, sarees, woollens, and other delicate garments.",
            400,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Ironing & Pressing",
            "Crisp ironing and pressing for shirts, trousers, and formal wear.",
            200,
        ),
    ],
    "Pest Control": [
        ServiceJob(
            "General Pest Control",
            "Treatment for common household pests like cockroaches and ants.",
            2000,
        ),
        ServiceJob(
            "Termite Treatment",
            "Targeted treatment for termite infestations in wooden furniture and structures.",
            3500,
            PriceType.starting_from,
        ),
        ServiceJob(
            "Rodent Control",
            "Safe trapping and prevention measures for mice and rats.",
            1800,
        ),
    ],
}


def jobs_for_category(service_category: str) -> list[ServiceJob]:
    """Every bookable job under a category — empty for an unknown category."""
    return SERVICE_JOBS.get(service_category, [])


def find_service_job(service_category: str, job_name: str) -> ServiceJob | None:
    """
    The job with this name under this category, or None if there's no such
    job. Name matching is case-insensitive and ignores surrounding spaces so
    a slightly-off client value doesn't silently lose the price, but it is
    otherwise exact — a job is only ever priced from the catalogue above.
    """
    wanted = job_name.strip().casefold()
    for job in jobs_for_category(service_category):
        if job.name.casefold() == wanted:
            return job
    return None