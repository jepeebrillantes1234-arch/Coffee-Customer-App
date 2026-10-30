import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/theme.dart';
import 'rider_theme.dart';

class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();
  final _plate = TextEditingController();
  final _license = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _savingPassword = false;
  bool _showPasswordForm = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _vehicle,
      _plate,
      _license,
      _currentPassword,
      _newPassword,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Api.I.riderProfile();
      final user = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : Api.I.user ?? {};
      final rider = data['rider_profile'] is Map
          ? Map<String, dynamic>.from(data['rider_profile'] as Map)
          : <String, dynamic>{};
      _name.text = user['name']?.toString() ?? '';
      _email.text = user['email']?.toString() ?? '';
      _phone.text = user['phone']?.toString() ?? '';
      _vehicle.text = rider['vehicle_type']?.toString() ?? '';
      _plate.text = rider['plate_number']?.toString() ?? '';
      _license.text = rider['license_no']?.toString() ?? '';
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your profile. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.I.updateProfile(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
      );
      await Api.I.updateRiderVehicle(
        vehicleType: _vehicle.text.trim(),
        plateNumber: _plate.text.trim(),
        licenseNumber: _license.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile settings saved.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save your profile. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePassword() async {
    if (_newPassword.text.length < 8) {
      setState(
        () => _error = 'Your new password must contain at least 8 characters.',
      );
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    setState(() {
      _savingPassword = true;
      _error = null;
    });
    try {
      await Api.I.changePassword(
        currentPassword: _currentPassword.text,
        password: _newPassword.text,
        passwordConfirmation: _confirmPassword.text,
      );
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      if (mounted) {
        setState(() => _showPasswordForm = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not change your password. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _changePhoto() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1200,
      );
      if (file == null) return;
      await Api.I.uploadAvatar(file.path);
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update your profile photo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Api.I.user ?? {};
    final avatar = user['avatar_url']?.toString();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: riderAccent(context)
                                .withValues(alpha: .12),
                            backgroundImage: avatar == null || avatar.isEmpty
                                ? null
                                : NetworkImage(avatar),
                            child: avatar == null || avatar.isEmpty
                                ? Icon(
                                    Icons.person_rounded,
                                    size: 48,
                                    color: riderAccent(context),
                                  )
                                : null,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: IconButton.filled(
                              onPressed: _changePhoto,
                              icon: const Icon(Icons.camera_alt_outlined),
                              tooltip: 'Change profile photo',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _name.text.isEmpty ? 'Rider' : _name.text,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text('Delivery Rider'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _section('Personal Information', Icons.person_outline, [
                  _field('Full name', _name, icon: Icons.badge_outlined),
                  const SizedBox(height: 12),
                  _field(
                    'Email address',
                    _email,
                    icon: Icons.email_outlined,
                    readOnly: true,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    'Phone number',
                    _phone,
                    icon: Icons.phone_outlined,
                    keyboard: TextInputType.phone,
                  ),
                ]),
                const SizedBox(height: 14),
                _section('Vehicle Information', Icons.two_wheeler_outlined, [
                  _field(
                    'Vehicle type',
                    _vehicle,
                    icon: Icons.directions_bike_outlined,
                    hint: 'Motorcycle, bicycle, etc.',
                  ),
                  const SizedBox(height: 12),
                  _field('Plate number', _plate, icon: Icons.pin_outlined),
                  const SizedBox(height: 12),
                  _field(
                    'License number',
                    _license,
                    icon: Icons.credit_card_outlined,
                  ),
                ]),
                const SizedBox(height: 14),
                _section('Preferences', Icons.tune_rounded, [
                  AnimatedBuilder(
                    animation: AppThemeController.I,
                    builder: (context, _) {
                      final mode = AppThemeController.I.mode;
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Dark mode'),
                        subtitle: const Text(
                          'Use a darker appearance in the app',
                        ),
                        secondary: Icon(
                          mode == ThemeMode.dark
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined,
                        ),
                        value: mode == ThemeMode.dark,
                        onChanged: (enabled) => AppThemeController.I.setMode(
                          enabled ? ThemeMode.dark : ThemeMode.light,
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 14),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Change Password'),
                        trailing: Icon(
                          _showPasswordForm
                              ? Icons.expand_less
                              : Icons.chevron_right,
                        ),
                        onTap: () => setState(() {
                          _showPasswordForm = !_showPasswordForm;
                          _error = null;
                        }),
                      ),
                      if (_showPasswordForm)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            children: [
                              _field(
                                'Current password',
                                _currentPassword,
                                password: true,
                              ),
                              const SizedBox(height: 10),
                              _field(
                                'New password',
                                _newPassword,
                                password: true,
                              ),
                              const SizedBox(height: 10),
                              _field(
                                'Confirm new password',
                                _confirmPassword,
                                password: true,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _savingPassword
                                      ? null
                                      : _savePassword,
                                  child: _savingPassword
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Save Password'),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: _saving
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: riderAccent(context)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    IconData? icon,
    TextInputType? keyboard,
    bool readOnly = false,
    bool password = false,
    String? hint,
  }) => TextField(
    controller: controller,
    readOnly: readOnly,
    keyboardType: keyboard,
    obscureText: password,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
    ),
  );
}
