import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/service_job.dart';
import 'api_config.dart';

class ServiceCatalogException implements Exception {
  final String message;
  ServiceCatalogException(this.message);

  @override
  String toString() => message;
}

/// Loads the priced service catalogue (every service, its bookable jobs, and
/// each job's price) from GET /api/services/catalog.
///
/// The server is the source of truth for prices — [fallbackCatalog] below is
/// only there so the app still shows something usable when the catalogue
/// can't be fetched, the same pattern [ProviderService.getCategories] already
/// uses for categories. A price shown from the fallback is only ever a
/// display value: the price actually recorded on a booking is looked up
/// server-side from its own catalogue when the booking is created, so a stale
/// fallback can never book a job at the wrong price.
class ServiceCatalogService {
  static Future<List<ServiceCatalogEntry>> getCatalog(String accessToken) async {
    http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('$apiBaseUrl/api/services/catalog'),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ServiceCatalogException('Request timed out. Please check your connection.');
    } catch (_) {
      throw ServiceCatalogException('Unable to reach the server. Please check your connection.');
    }

    if (response.statusCode == 401) {
      throw ServiceCatalogException('Your session has expired. Please log in again.');
    }
    if (response.statusCode != 200) {
      throw ServiceCatalogException('Failed to load services.');
    }

    try {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) => ServiceCatalogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw ServiceCatalogException('Unexpected response from server.');
    }
  }

  /// Same as [getCatalog], but returns [fallbackCatalog] instead of throwing
  /// when the request fails — for the home screen, which should still list
  /// services when the catalogue endpoint is briefly unreachable.
  static Future<List<ServiceCatalogEntry>> getCatalogOrFallback(String accessToken) async {
    try {
      final catalog = await getCatalog(accessToken);
      if (catalog.isNotEmpty) return catalog;
    } catch (_) {
      // fall through to the local copy
    }
    return fallbackCatalog;
  }

  /// Offline copy of the catalogue. Keep in step with
  /// `SERVICE_JOBS` in the backend's app/constants.py — that file is the
  /// source of truth, this is a mirror for when the server can't be reached.
  static const List<ServiceCatalogEntry> fallbackCatalog = [
    ServiceCatalogEntry(
      serviceCategory: 'Electrical',
      jobs: [
        ServiceJob(
          name: 'Fan Installation',
          description: 'Mounting and wiring a ceiling or wall fan, including testing the regulator.',
          price: 600,
          priceLabel: 'Rs. 600',
        ),
        ServiceJob(
          name: 'Switchboard & Socket Repair',
          description:
              'Fixing faulty switches, sockets, and switchboards, including sparking or tripping issues.',
          price: 500,
          priceLabel: 'Rs. 500',
        ),
        ServiceJob(
          name: 'Light Fitting Installation',
          description: 'Installing or repairing tube lights, panel lights, and other light fixtures.',
          price: 450,
          priceLabel: 'Rs. 450',
        ),
        ServiceJob(
          name: 'Wiring & Rewiring',
          description: 'Inspecting and replacing old or unsafe household wiring.',
          price: 1500,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 1,500',
        ),
      ],
    ),
    ServiceCatalogEntry(
      serviceCategory: 'Cleaning',
      jobs: [
        ServiceJob(
          name: 'Room Cleaning',
          description: 'Sweeping, mopping, dusting, and tidying for a single room.',
          price: 500,
          priceLabel: 'Rs. 500',
        ),
        ServiceJob(
          name: 'Deep House Cleaning',
          description:
              'A thorough top-to-bottom clean covering floors, windows, kitchen surfaces, and bathrooms — ideal before a festival, move-in, or move-out.',
          price: 2500,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 2,500',
        ),
        ServiceJob(
          name: 'Bathroom & Kitchen Cleaning',
          description:
              'Focused scrubbing and sanitizing of tiles, sinks, and stovetops to cut through built-up grease and grime.',
          price: 1200,
          priceLabel: 'Rs. 1,200',
        ),
        ServiceJob(
          name: 'Sofa & Carpet Cleaning',
          description:
              'Steam or shampoo cleaning for sofas, carpets, and rugs to lift dust, stains, and odours.',
          price: 1500,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 1,500',
        ),
      ],
    ),
    ServiceCatalogEntry(
      serviceCategory: 'Plumbing',
      jobs: [
        ServiceJob(
          name: 'Leak & Pipe Repair',
          description:
              'Fixing leaking taps, pipes, and joints to stop water wastage and prevent damage to walls and floors.',
          price: 700,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 700',
        ),
        ServiceJob(
          name: 'Tap & Fixture Installation',
          description: 'Installing or replacing taps, showers, and wash-basin fittings.',
          price: 600,
          priceLabel: 'Rs. 600',
        ),
        ServiceJob(
          name: 'Water Tank Cleaning',
          description: 'Draining, scrubbing, and sanitizing overhead or underground water tanks.',
          price: 1500,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 1,500',
        ),
      ],
    ),
    ServiceCatalogEntry(
      serviceCategory: 'Painting',
      jobs: [
        ServiceJob(
          name: 'Interior Wall Painting',
          description: 'Full or touch-up painting for bedrooms, living rooms, and ceilings.',
          price: 3000,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 3,000',
        ),
        ServiceJob(
          name: 'Exterior Wall Painting',
          description: 'Weatherproof painting for outside walls and boundary walls.',
          price: 5000,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 5,000',
        ),
        ServiceJob(
          name: 'Waterproofing & Wall Repair',
          description: 'Treating damp patches, cracks, and seepage before repainting.',
          price: 2500,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 2,500',
        ),
      ],
    ),
    ServiceCatalogEntry(
      serviceCategory: 'Appliance Repair',
      jobs: [
        ServiceJob(
          name: 'Washing Machine Repair',
          description: 'Diagnosing and fixing drainage, spinning, or power issues.',
          price: 800,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 800',
        ),
        ServiceJob(
          name: 'Refrigerator Repair',
          description: 'Fixing cooling problems, unusual noise, or leaks.',
          price: 900,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 900',
        ),
        ServiceJob(
          name: 'Microwave & Oven Repair',
          description: 'Repairing heating and control issues on microwaves and ovens.',
          price: 700,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 700',
        ),
      ],
    ),
    ServiceCatalogEntry(
      serviceCategory: 'Carpentry',
      jobs: [
        ServiceJob(
          name: 'Furniture Repair',
          description: 'Fixing broken chairs, tables, cupboards, and other wooden furniture.',
          price: 800,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 800',
        ),
        ServiceJob(
          name: 'Door & Window Fitting',
          description:
              "Repairing or installing doors, windows, hinges, and locks that stick or don't close properly.",
          price: 1000,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 1,000',
        ),
        ServiceJob(
          name: 'Custom Furniture Assembly',
          description: 'Assembling flat-pack or made-to-order furniture at your home.',
          price: 1200,
          priceLabel: 'Rs. 1,200',
        ),
      ],
    ),
    ServiceCatalogEntry(
      serviceCategory: 'Laundry',
      jobs: [
        ServiceJob(
          name: 'Wash & Fold',
          description: 'Everyday clothes washed, dried, and neatly folded, ready to put away.',
          price: 300,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 300',
        ),
        ServiceJob(
          name: 'Dry Cleaning',
          description:
              'Professional cleaning for suits, sarees, woollens, and other delicate garments.',
          price: 400,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 400',
        ),
        ServiceJob(
          name: 'Ironing & Pressing',
          description: 'Crisp ironing and pressing for shirts, trousers, and formal wear.',
          price: 200,
          priceLabel: 'Rs. 200',
        ),
      ],
    ),
    ServiceCatalogEntry(
      serviceCategory: 'Pest Control',
      jobs: [
        ServiceJob(
          name: 'General Pest Control',
          description: 'Treatment for common household pests like cockroaches and ants.',
          price: 2000,
          priceLabel: 'Rs. 2,000',
        ),
        ServiceJob(
          name: 'Termite Treatment',
          description:
              'Targeted treatment for termite infestations in wooden furniture and structures.',
          price: 3500,
          priceType: PriceType.startingFrom,
          priceLabel: 'From Rs. 3,500',
        ),
        ServiceJob(
          name: 'Rodent Control',
          description: 'Safe trapping and prevention measures for mice and rats.',
          price: 1800,
          priceLabel: 'Rs. 1,800',
        ),
      ],
    ),
  ];
}
