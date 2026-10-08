import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../main.dart';
import '../services/payment_service.dart';

class EsewaPaymentPage extends StatefulWidget {
  final String accessToken;
  final EsewaPaymentInit payment;

  const EsewaPaymentPage({
    super.key,
    required this.accessToken,
    required this.payment,
  });

  @override
  State<EsewaPaymentPage> createState() => _EsewaPaymentPageState();
}

class _EsewaPaymentPageState extends State<EsewaPaymentPage> {
  late final WebViewController _controller;
  bool _handledRedirect = false;
  // Set once eSewa reports success; the money may have moved, so never
  // auto-cancel after this point, even if our verification call fails.
  String? _paidData;
  bool _loading = true;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: _handleNavigation,
        ),
      );
    _loadPaymentForm();
  }

  Future<void> _loadPaymentForm() async {
    final formBody = Uri(queryParameters: widget.payment.fields).query;
    await _controller.loadRequest(
      Uri.parse(widget.payment.formUrl),
      method: LoadRequestMethod.post,
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: utf8.encode(formBody),
    );
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null || _handledRedirect) return NavigationDecision.navigate;

    if (uri.path.endsWith('/api/bookings/esewa/success')) {
      final data = _extractData(request.url);
      if (data != null && data.isNotEmpty) {
        _handledRedirect = true;
        _finishSuccess(data);
        return NavigationDecision.prevent;
      }
    }

    if (uri.path.endsWith('/api/bookings/esewa/failure')) {
      _handledRedirect = true;
      _finishFailure();
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  /// eSewa appends "?data=..." even when success_url already has a query
  /// string, so Uri.queryParameters can miss it. Pull it out of the raw URL.
  String? _extractData(String url) {
    final match = RegExp(r'[?&]data=([^&?#]+)').firstMatch(url);
    if (match == null) return null;
    return Uri.decodeComponent(match.group(1)!);
  }

  Future<void> _finishSuccess(String data) async {
    if (!mounted) return;
    _paidData = data;
    try {
      final booking = await PaymentService.verify(
        accessToken: widget.accessToken,
        bookingId: widget.payment.bookingId,
        data: data,
      );
      if (!mounted) return;
      if (booking.paymentStatus == 'paid') {
        Navigator.pop(context, booking);
        return;
      }
      // The server only reports "paid" once eSewa itself has confirmed the
      // payment. Anything else is not a success.
      if (booking.paymentStatus == 'pending') {
        // eSewa has not finalised the transaction yet — let the customer
        // re-check instead of telling them it worked.
        _handledRedirect = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('eSewa has not confirmed the payment yet.'),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Check again',
              textColor: Colors.white,
              onPressed: () {
                _handledRedirect = true;
                _finishSuccess(data);
              },
            ),
          ),
        );
        return;
      }
      // failed / cancelled / refunded: hand the booking back so the details
      // page shows the real state.
      Navigator.pop(context, booking);
    } on PaymentServiceException catch (e) {
      if (!mounted) return;
      _handledRedirect = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              _handledRedirect = true;
              _finishSuccess(data);
            },
          ),
        ),
      );
    }
  }

  Future<void> _finishFailure() async {
    try {
      await PaymentService.cancel(
        accessToken: widget.accessToken,
        bookingId: widget.payment.bookingId,
      );
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<bool> _close() async {
    if (_handledRedirect || _paidData != null) return true;
    try {
      await PaymentService.cancel(
        accessToken: widget.accessToken,
        bookingId: widget.payment.bookingId,
      );
    } catch (_) {}
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _close();
        if (shouldPop && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pay with eSewa'),
          backgroundColor: Colors.white,
          foregroundColor: kDarkText,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'Cancel payment',
              onPressed: () async {
                final shouldPop = await _close();
                if (shouldPop && mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_loading) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}