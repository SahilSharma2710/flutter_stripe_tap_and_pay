import 'package:flutter/material.dart';
import 'package:mek_stripe_terminal/mek_stripe_terminal.dart';

class PaymentPage extends StatefulWidget {
  final Terminal terminal;

  const PaymentPage({super.key, required this.terminal});
  @override
  _PaymentPageState createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();

  PaymentIntent? _paymentIntent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showSnackBar("Connected");
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<bool> _createPaymentIntent(Terminal terminal, String amount) async {
    final paymentIntent =
        await terminal.createPaymentIntent(PaymentIntentParameters(
      amount:
          (double.parse(double.parse(amount).toStringAsFixed(2)) * 100).ceil(),
      currency: "usd",
      captureMethod: CaptureMethod.automatic,
      paymentMethodTypes: [PaymentMethodType.cardPresent],
    ));
    _paymentIntent = paymentIntent;
    if (_paymentIntent == null) {
      showSnackBar('Payment intent is not created!');
    }

    return await _collectPaymentMethod(terminal, _paymentIntent!);
  }

  Future<bool> _collectPaymentMethod(
      Terminal terminal, PaymentIntent paymentIntent) async {
    final collectingPaymentMethod = terminal.collectPaymentMethod(
      paymentIntent,
      skipTipping: true,
    );

    try {
      final paymentIntentWithPaymentMethod = await collectingPaymentMethod;
      _paymentIntent = paymentIntentWithPaymentMethod;
      await _confirmPaymentIntent(terminal, _paymentIntent!).then((value) {});
      return true;
    } on TerminalException catch (exception) {
      switch (exception.code) {
        case TerminalExceptionCode.canceled:
          showSnackBar('Collecting Payment method is cancelled!');
          return false;
        default:
          rethrow;
      }
    }
  }

  Future<void> _confirmPaymentIntent(
      Terminal terminal, PaymentIntent paymentIntent) async {
    try {
      final processedPaymentIntent =
          await terminal.confirmPaymentIntent(paymentIntent);
      _paymentIntent = processedPaymentIntent;
      showSnackBar('Payment processed!');
    } catch (e) {
      showSnackBar('Inside collect payment exception ${e.toString()}');

      print(e.toString());
    }
    // navigate to payment success screen
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
      ));
  }

  void _collectPayment() async {
    if (_formKey.currentState!.validate()) {
      bool status =
          await _createPaymentIntent(widget.terminal, _amountController.text);
      if (status) {
        showSnackBar('Payment Collected: ${_amountController.text}');
      } else {
        showSnackBar('Payment Canceled');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Collect Payment',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24),
        ),
        backgroundColor: Colors.teal,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                height: 100,
              ),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Enter Amount',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  return null;
                },
              ),
              SizedBox(height: 40),
              ElevatedButton(
                onPressed: _collectPayment,
                child: Text('Collect Payment'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.teal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
