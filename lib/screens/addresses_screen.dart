import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/reverse_geocoder.dart';
import '../core/util.dart';

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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _AddressFormScreen()),
    );
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
      MaterialPageRoute(
        builder: (_) => _AddressFormScreen(address: address),
      ),
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
        title: Text(widget.selectionMode ? 'Choose delivery address' : 'Saved addresses'),
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
                    final lat = dbl(address['latitude']);
                    final lng = dbl(address['longitude']);
                    return Card(
                      child: ListTile(
                        onTap: widget.selectionMode
                            ? () => _choose(address)
                            : null,
                        leading: const CircleAvatar(
                          child: Icon(Icons.place_outlined),
                        ),
                        title: Text('${address['label'] ?? 'Saved address'}'),
                        subtitle: Text(
                          '${address['full_address'] ?? ''}\n${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        ),
                        isThreeLine: true,
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
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  bool _locating = false;
  bool _saving = false;
  bool _resolving = false;
  int _resolveSequence = 0;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    if (address != null) {
      _label.text = '${address['label'] ?? ''}';
      _fullAddress.text = '${address['full_address'] ?? ''}';
      _latitude.text = '${address['latitude'] ?? ''}';
      _longitude.text = '${address['longitude'] ?? ''}';
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _fullAddress.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _lookupCurrentCoordinates(double latitude, double longitude) async {
    final sequence = ++_resolveSequence;
    setState(() => _resolving = true);
    try {
      final place = await ReverseGeocoder.resolve(latitude, longitude);
      if (!mounted || sequence != _resolveSequence) return;
      if (place == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Address lookup failed. Please enter the full address manually.'),
          ),
        );
        return;
      }
      _fullAddress.text = place.address;
      if (_label.text.trim().isEmpty) _label.text = place.name;
    } finally {
      if (mounted && sequence == _resolveSequence) {
        setState(() => _resolving = false);
      }
    }
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw ApiException('Turn on location services to use GPS.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw ApiException('Allow location permission to use GPS.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude.text = position.latitude.toStringAsFixed(6);
        _longitude.text = position.longitude.toStringAsFixed(6);
      });
      await _lookupCurrentCoordinates(position.latitude, position.longitude);
    } catch (error) {
      if (mounted) {
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
    final fullAddress = _fullAddress.text.trim();
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
          content: Text('Enter a location name, full address, and valid coordinates. Use GPS to fill in coordinates.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await Api.I.saveAddress(label, fullAddress, latitude, longitude);
      final oldId = int.tryParse('${widget.address?['id']}');
      if (oldId != null) await Api.I.deleteAddress(oldId);
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
      appBar: AppBar(
        title: Text(editing ? 'Edit address' : 'Add address'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing ? 'Update your saved delivery location.' : 'Add a delivery location to use at checkout.',
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
                label: Text(_locating ? 'Getting location...' : 'Use current GPS location'),
              ),
              if (_resolving) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 4),
                const Text('Finding the address...'),
              ],
              const SizedBox(height: 10),
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
              const SizedBox(height: 8),
              Text(
                'GPS fills in the coordinates. You can edit the address details above before saving.',
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
