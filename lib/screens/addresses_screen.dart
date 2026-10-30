import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/reverse_geocoder.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key, this.selectionMode = false});

  final bool selectionMode;

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await Api.I.addresses();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const _AddressFormScreen()));
    if (saved == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> address) async {
    final id = int.tryParse('${address['id']}');
    if (id == null) return;
    try {
      await Api.I.deleteAddress(id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> address) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _AddressFormScreen(address: address)),
    );
    if (result == true) await _load();
  }

  void _choose(Map<String, dynamic> address) {
    Navigator.of(context).pop(address);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.selectionMode ? 'Choose delivery address' : 'Saved addresses',
        ),
        actions: [
          IconButton(
            tooltip: 'Add address',
            onPressed: _add,
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      widget.selectionMode
                          ? 'No saved addresses yet. Add an address to continue.'
                          : 'No saved addresses yet.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.add),
                      label: const Text('Add address'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, index) {
                final address = _items[index];
                final label = '${address['label'] ?? 'Saved address'}'.trim();
                final fullAddress =
                    '${address['formatted_address'] ?? address['full_address'] ?? ''}'
                        .trim();
                return Card(
                  child: ListTile(
                    onTap: widget.selectionMode ? () => _choose(address) : null,
                    leading: const CircleAvatar(
                      child: Icon(Icons.place_outlined),
                    ),
                    title: Text(
                      fullAddress.isEmpty ? label : fullAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: fullAddress.isNotEmpty && label != fullAddress
                        ? Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: widget.selectionMode
                        ? const Icon(Icons.chevron_right_rounded)
                        : Wrap(
                            spacing: 0,
                            children: [
                              IconButton(
                                tooltip: 'Edit address',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(address),
                              ),
                              IconButton(
                                tooltip: 'Delete address',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(address),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
    );
  }
}

class _AddressFormScreen extends StatefulWidget {
  const _AddressFormScreen({this.address});

  final Map<String, dynamic>? address;

  @override
  State<_AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<_AddressFormScreen> {
  final _label = TextEditingController();
  final _fullAddress = TextEditingController();
  final _street = TextEditingController();
  final _barangay = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();
  final _postalCode = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  bool _locating = false;
  bool _saving = false;
  bool _resolving = false;
  String? _locationMessage;
  int _resolveSequence = 0;
  bool _fullAddressEdited = false;
  bool _structuredAddressEdited = false;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    if (address != null) {
      _label.text = '${address['label'] ?? ''}';
      _fullAddress.text =
          '${address['formatted_address'] ?? address['full_address'] ?? ''}';
      _street.text = '${address['street'] ?? ''}';
      _barangay.text = '${address['barangay'] ?? ''}';
      _city.text = '${address['city'] ?? ''}';
      _province.text = '${address['province'] ?? ''}';
      _postalCode.text = '${address['postal_code'] ?? ''}';
      _latitude.text = '${address['latitude'] ?? ''}';
      _longitude.text = '${address['longitude'] ?? ''}';
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _fullAddress.dispose();
    _street.dispose();
    _barangay.dispose();
    _city.dispose();
    _province.dispose();
    _postalCode.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _lookupCurrentCoordinates(
    double latitude,
    double longitude,
  ) async {
    final sequence = ++_resolveSequence;
    setState(() => _resolving = true);
    try {
      final place = await ReverseGeocoder.resolve(latitude, longitude);
      if (!mounted || sequence != _resolveSequence) return;
      if (place == null) {
        setState(() {
          _locationMessage = 'GPS pin saved, but a readable address could not be found. Enter the address manually; the coordinates are retained.';
          if (_label.text.trim().isEmpty) _label.text = 'Current location';
        });
        return;
      }
      setState(() {
        // Do not replace details the customer has already entered. Fill each
        // structured field only when it is still blank.
        if (_street.text.trim().isEmpty) _street.text = place.street;
        if (_barangay.text.trim().isEmpty) _barangay.text = place.barangay;
        if (_city.text.trim().isEmpty) _city.text = place.city;
        if (_province.text.trim().isEmpty) _province.text = place.province;
        if (_postalCode.text.trim().isEmpty) {
          _postalCode.text = place.postalCode;
        }
        if (_fullAddress.text.trim().isEmpty) _fullAddress.text = place.address;
        if (_label.text.trim().isEmpty || _label.text == 'Current location') {
          _label.text = place.name;
        }
        _locationMessage = '${String.fromCharCode(0x1F4CD)} ${place.address}';
      });
    } finally {
      if (mounted && sequence == _resolveSequence) {
        setState(() => _resolving = false);
      }
    }
  }

  Future<bool> _showLocationPrompt({
    required String title,
    required String message,
    required String actionLabel,
    required String cancelLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(cancelLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _useGps() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        final openSettings = await _showLocationPrompt(
          title: 'Turn on location services',
          message: 'Enable your device location services to get the delivery pin. You can return here and try again afterward.',
          actionLabel: 'Open location settings',
          cancelLabel: 'Not now',
        );
        if (openSettings && mounted) await Geolocator.openLocationSettings();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        final openSettings = await _showLocationPrompt(
          title: 'Location permission is blocked',
          message: 'Allow location access while using the app in your app settings, then return and try again. Background location access is not needed.',
          actionLabel: 'Open app settings',
          cancelLabel: 'Cancel',
        );
        if (openSettings && mounted) await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        final retry = await _showLocationPrompt(
          title: 'Location permission needed',
          message: 'Allow location access while using the app to generate your delivery address. You can try again or continue without GPS.',
          actionLabel: 'Try again',
          cancelLabel: 'Cancel',
        );
        if (retry && mounted) await _useGps();
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        // The backend stores seven decimal places; keep that precision in the
        // editable controllers so saving an address does not round the pin.
        _latitude.text = position.latitude.toStringAsFixed(7);
        _longitude.text = position.longitude.toStringAsFixed(7);
        _locationMessage = 'GPS pin acquired. Finding the place name...';
      });
      await _lookupCurrentCoordinates(position.latitude, position.longitude);
    } catch (error) {
      if (mounted) {
        if (error is LocationServiceDisabledException) {
          final openSettings = await _showLocationPrompt(
            title: 'Turn on location services',
            message: 'Enable your device location services to get the delivery pin. You can return here and try again afterward.',
            actionLabel: 'Open location settings',
            cancelLabel: 'Not now',
          );
          if (openSettings && mounted) await Geolocator.openLocationSettings();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('ApiException: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final structuredParts = [
      _street.text.trim(),
      _barangay.text.trim(),
      _city.text.trim(),
      _province.text.trim(),
      _postalCode.text.trim(),
    ].where((part) => part.isNotEmpty).toList();
    final structuredAddress = structuredParts.join(', ');
    final fullAddress =
        _fullAddressEdited ||
            (!_structuredAddressEdited && _fullAddress.text.trim().isNotEmpty)
        ? _fullAddress.text.trim()
        : structuredAddress;
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    if (label.isEmpty ||
        fullAddress.isEmpty ||
        latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a location name, full address, and valid coordinates. Use GPS to fill in coordinates.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final oldId = int.tryParse('${widget.address?['id']}');
      if (oldId == null) {
        await Api.I.saveAddress(
          label,
          fullAddress,
          latitude,
          longitude,
          street: _street.text.trim(),
          barangay: _barangay.text.trim(),
          city: _city.text.trim(),
          province: _province.text.trim(),
          postalCode: _postalCode.text.trim(),
          formattedAddress: fullAddress,
        );
      } else {
        await Api.I.updateAddress(
          oldId,
          label,
          fullAddress,
          latitude,
          longitude,
          street: _street.text.trim(),
          barangay: _barangay.text.trim(),
          city: _city.text.trim(),
          province: _province.text.trim(),
          postalCode: _postalCode.text.trim(),
          formattedAddress: fullAddress,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.address != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit address' : 'Add address')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing
                    ? 'Update your saved delivery location.'
                    : 'Add a delivery location to use at checkout.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _label,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Location name',
                  hintText: 'Home, Work, or another name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.bookmark_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _fullAddress,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full address',
                  hintText: 'House/street, barangay, city, province, country',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                onChanged: (_) => _fullAddressEdited = true,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _street,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Street / House / Building',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.signpost_outlined),
                ),
                onChanged: (_) => _structuredAddressEdited = true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _barangay,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Barangay',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                onChanged: (_) => _structuredAddressEdited = true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'City / Municipality',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _structuredAddressEdited = true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _province,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Province',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _structuredAddressEdited = true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _postalCode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Postal code (optional)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _structuredAddressEdited = true,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _locating ? null : _useGps,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  _locating
                      ? 'Getting location...'
                      : 'Use current GPS location',
                ),
              ),
              if (_resolving) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 4),
                const Text('Finding the address...'),
              ],
              if (_locationMessage != null && !_resolving) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_locationMessage!)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Map coordinates (advanced)'),
                subtitle: Text(
                  _latitude.text.isEmpty || _longitude.text.isEmpty
                      ? 'Used internally for delivery and tracking'
                      : 'GPS pin saved for delivery and tracking',
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'GPS fills in the map pin. You can edit the address details above before saving.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save address'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
