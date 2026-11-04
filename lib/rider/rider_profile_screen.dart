import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../screens/auth_screen.dart';
import '../screens/customer_service_sheet.dart';
import 'rider_home_screen.dart';
import 'rider_location_service.dart';
import 'rider_membership_card_deliveries_screen.dart';
import 'rider_reports_screen.dart';
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
  bool _availabilityBusy = false;
  bool _available = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _restoreActiveTracking();
  }

  Future<void> _restoreActiveTracking() async {
    try {
      final response = await Api.I.deliveries();
      final items = response['items'];
      if (items is! List) return;
      final ids = items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((delivery) => delivery['status'] == 'on_the_way')
          .map((delivery) => delivery['id'])
          .whereType<num>()
          .map((id) => id.toInt())
          .toSet();
      await LocationService.I.syncActiveDeliveries(ids);
    } catch (_) {
      // Keep the current location service state if the network is unavailable.
    }
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
      _available = rider['is_available'] == true;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your profile. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _save() async {
    if (_name.text.trim().isEmpty) {
      return 'Enter your full name.';
    }
    setState(() {
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
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not save your profile. Please try again.';
    }
  }

  Future<String?> _savePassword() async {
    if (_newPassword.text.length < 8) {
      return 'Your new password must contain at least 8 characters.';
    }
    if (_newPassword.text != _confirmPassword.text) {
      return 'The new passwords do not match.';
    }
    setState(() {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not change your password. Please try again.';
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

  Future<void> _openEditProfile(String? avatar) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RiderEditProfileScreen(
          name: _name,
          email: _email,
          phone: _phone,
          vehicle: _vehicle,
          plate: _plate,
          license: _license,
          getAvatarUrl: () => Api.I.user?['avatar_url']?.toString() ?? avatar,
          onSave: _save,
          onChangePhoto: _changePhoto,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openChangePassword() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RiderChangePasswordScreen(
        currentPassword: _currentPassword,
        newPassword: _newPassword,
        confirmPassword: _confirmPassword,
        onSave: _savePassword,
      ),
    ),
  );

  Future<void> _openSettings() => showDialog<void>(
    context: context,
    builder: (_) => AnimatedBuilder(
      animation: AppThemeController.I,
      builder: (context, _) {
        final dark = AppThemeController.I.mode == ThemeMode.dark;
        return AlertDialog(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          content: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(dark ? 'Dark Mode' : 'Light Mode'),
            value: dark,
            onChanged: (enabled) => AppThemeController.I.setMode(
              enabled ? ThemeMode.dark : ThemeMode.light,
            ),
          ),
        );
      },
    ),
  );

  Future<void> _openWorkArea(int tab) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RiderHomeScreen(initialTab: tab)));
  }

  Future<void> _toggleAvailability(bool available) async {
    if (_availabilityBusy) return;
    setState(() => _availabilityBusy = true);
    try {
      final result = await Api.I.setAvailability(available);
      if (mounted) setState(() => _available = result);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _availabilityBusy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to access your rider account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocationService.I.stop();
    await Api.I.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  void _openAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'KJM Coffee Shop Rider',
      applicationVersion: 'Delivery partner app',
      applicationIcon: const Icon(Icons.delivery_dining_rounded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Api.I.user ?? {};
    final avatar = user['avatar_url']?.toString();
    final scheme = Theme.of(context).colorScheme;
    return RiderVisualTheme(
      child: Scaffold(
        appBar: RiderAppBar(
          title: 'Rider Profile',
          actions: [
            IconButton(
              tooltip: 'Settings',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: RiderImageBackground(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _profileHero(context, avatar),
                    const SizedBox(height: 16),
                    _profileQuickInfo(context),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      secondary: Icon(
                        _available
                            ? Icons.wifi_tethering_rounded
                            : Icons.wifi_tethering_off_rounded,
                        color: _available
                            ? const Color(0xFF228A60)
                            : riderSecondaryText(context),
                      ),
                      title: Text(
                        _available ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: riderPrimaryText(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        _available
                            ? 'Ready to receive delivery assignments'
                            : 'Turn on to receive new delivery assignments',
                        style: TextStyle(color: riderSecondaryText(context)),
                      ),
                      value: _available,
                      onChanged: _availabilityBusy ? null : _toggleAvailability,
                    ),
                    const SizedBox(height: 18),
                    _menuSection(context, 'Account', [
                      _menuTile(
                        context,
                        Icons.edit_outlined,
                        'Edit Profile',
                        'Update your personal and vehicle information',
                        () => _openEditProfile(avatar),
                      ),
                      _menuTile(
                        context,
                        Icons.lock_outline_rounded,
                        'Change Password',
                        'Update your account password',
                        _openChangePassword,
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _menuSection(context, 'Rider menu', [
                      _menuTile(
                        context,
                        Icons.credit_card_outlined,
                        'Membership Card Deliveries',
                        'View assigned physical card deliveries',
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const RiderMembershipCardDeliveriesScreen(),
                          ),
                        ),
                      ),
                      _menuTile(
                        context,
                        Icons.delivery_dining_outlined,
                        'My Deliveries',
                        'View and manage assigned deliveries',
                        () => _openWorkArea(1),
                      ),
                      _menuTile(
                        context,
                        Icons.history_rounded,
                        'Delivery History',
                        'Review completed and declined deliveries',
                        () => _openWorkArea(2),
                      ),
                      _menuTile(
                        context,
                        Icons.bar_chart_rounded,
                        'Reports',
                        'See delivery totals and trends',
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RiderReportsScreen(),
                          ),
                        ),
                      ),
                      _menuTile(
                        context,
                        Icons.support_agent_rounded,
                        'Customer Service',
                        'Contact KJM Coffee Shop support',
                        () => showCustomerServiceSheet(context),
                      ),
                      _menuTile(
                        context,
                        Icons.info_outline_rounded,
                        'About',
                        'About the KJM rider app',
                        _openAbout,
                      ),
                    ]),
                    const SizedBox(height: 14),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Log out'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _profileHero(BuildContext context, String? avatar) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
    child: Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: riderGold,
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 48,
                backgroundColor: Theme.of(context).colorScheme.surface,
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
            ),
            Positioned(
              right: -2,
              bottom: 0,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _changePhoto,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                tooltip: 'Change profile photo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _name.text.trim().isEmpty ? 'Rider' : _name.text.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: riderPrimaryText(context),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'Delivery Rider',
          style: TextStyle(color: riderSecondaryText(context), fontSize: 14),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _available
                ? const Color(0xFF176B2C)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: _available ? const Color(0xFF76F08D) : riderMutedBrown,
              ),
              const SizedBox(width: 6),
              Text(
                _available ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  color: _available ? Colors.white : riderPrimaryText(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: .5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _profileQuickInfo(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Column(
      children: [
        _quickInfoRow(context, Icons.call_rounded, _phone.text, 'Phone number'),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        _quickInfoRow(
          context,
          Icons.email_rounded,
          _email.text,
          'Email address',
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        _quickInfoRow(
          context,
          Icons.two_wheeler_rounded,
          [
            _vehicle.text.trim(),
            if (_plate.text.trim().isNotEmpty) 'Plate: ${_plate.text.trim()}',
          ].where((part) => part.trim().isNotEmpty).join(' · '),
          'Vehicle used for deliveries',
        ),
      ],
    ),
  );

  Widget _quickInfoRow(
    BuildContext context,
    IconData icon,
    String value,
    String fallback,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: riderAccent(context), size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value.trim().isEmpty ? fallback : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: riderPrimaryText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _menuSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
        child: Text(
          title,
          style: TextStyle(
            color: riderSecondaryText(context),
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      ),
      ...children,
    ],
  );

  Widget _menuTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    leading: Icon(icon, color: riderAccent(context)),
    title: Text(
      title,
      style: TextStyle(
        color: riderPrimaryText(context),
        fontWeight: FontWeight.w700,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(color: riderSecondaryText(context)),
    ),
    trailing: Icon(
      Icons.chevron_right_rounded,
      color: riderSecondaryText(context),
    ),
    onTap: onTap,
  );
}

class RiderEditProfileScreen extends StatefulWidget {
  const RiderEditProfileScreen({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.vehicle,
    required this.plate,
    required this.license,
    required this.getAvatarUrl,
    required this.onSave,
    required this.onChangePhoto,
  });

  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController vehicle;
  final TextEditingController plate;
  final TextEditingController license;
  final String? Function() getAvatarUrl;
  final Future<String?> Function() onSave;
  final Future<void> Function() onChangePhoto;

  @override
  State<RiderEditProfileScreen> createState() => _RiderEditProfileScreenState();
}

class _RiderEditProfileScreenState extends State<RiderEditProfileScreen> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => RiderVisualTheme(
    child: Scaffold(
      appBar: const RiderAppBar(title: 'Edit Profile'),
      body: RiderImageBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    backgroundImage: widget.getAvatarUrl()?.isNotEmpty == true
                        ? NetworkImage(widget.getAvatarUrl()!)
                        : null,
                    child: widget.getAvatarUrl()?.isNotEmpty == true
                        ? null
                        : Icon(
                            Icons.person_rounded,
                            size: 46,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      await widget.onChangePhoto();
                      if (mounted) setState(() {});
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: riderAccent(context),
                    ),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Change Photo'),
                  ),
                ],
              ),
            ),
            _profileSection(
              context,
              'Personal Information',
              Icons.person_outline,
              [
                _profileInput(
                  context,
                  'Name',
                  widget.name,
                  Icons.badge_outlined,
                ),
                _profileInput(
                  context,
                  'Phone',
                  widget.phone,
                  Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                ),
                _profileInput(
                  context,
                  'Email',
                  widget.email,
                  Icons.email_outlined,
                  readOnly: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _profileSection(
              context,
              'Vehicle Information',
              Icons.two_wheeler_outlined,
              [
                _profileInput(
                  context,
                  'Vehicle type',
                  widget.vehicle,
                  Icons.directions_bike_outlined,
                ),
                _profileInput(
                  context,
                  'Plate number',
                  widget.plate,
                  Icons.pin_outlined,
                ),
                _profileInput(
                  context,
                  'License number',
                  widget.license,
                  Icons.credit_card_outlined,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class RiderChangePasswordScreen extends StatefulWidget {
  const RiderChangePasswordScreen({
    super.key,
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
    required this.onSave,
  });

  final TextEditingController currentPassword;
  final TextEditingController newPassword;
  final TextEditingController confirmPassword;
  final Future<String?> Function() onSave;

  @override
  State<RiderChangePasswordScreen> createState() =>
      _RiderChangePasswordScreenState();
}

class _RiderChangePasswordScreenState extends State<RiderChangePasswordScreen> {
  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) Navigator.of(context).pop();
  }

  Widget _passwordField(
    String label,
    TextEditingController controller,
    bool visible,
    ValueChanged<bool> onVisibility,
  ) => TextField(
    controller: controller,
    obscureText: !visible,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        tooltip: visible ? 'Hide password' : 'Show password',
        onPressed: () => onVisibility(!visible),
        icon: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => RiderVisualTheme(
    child: Scaffold(
      appBar: const RiderAppBar(title: 'Change Password'),
      body: RiderImageBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _passwordField(
              'Current Password',
              widget.currentPassword,
              _showCurrent,
              (v) => setState(() => _showCurrent = v),
            ),
            const SizedBox(height: 14),
            _passwordField(
              'New Password',
              widget.newPassword,
              _showNew,
              (v) => setState(() => _showNew = v),
            ),
            const SizedBox(height: 14),
            _passwordField(
              'Confirm New Password',
              widget.confirmPassword,
              _showConfirm,
              (v) => setState(() => _showConfirm = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_saving ? 'Saving…' : 'Save Password'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _profileSection(
  BuildContext context,
  String title,
  IconData icon,
  List<Widget> fields,
) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, color: riderAccent(context)),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: riderAccent(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      ...fields.map(
        (field) =>
            Padding(padding: const EdgeInsets.only(bottom: 12), child: field),
      ),
    ],
  ),
);

Widget _profileInput(
  BuildContext context,
  String label,
  TextEditingController controller,
  IconData icon, {
  TextInputType? keyboard,
  bool readOnly = false,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final accent = riderAccent(context);
  final fieldSurface = dark ? const Color(0xFF302720) : const Color(0xFFFFFCF7);
  final fieldBorder = dark ? const Color(0xFF5E4C3F) : const Color(0xFFE2D3C1);
  return TextField(
    controller: controller,
    keyboardType: keyboard,
    readOnly: readOnly,
    style: TextStyle(color: riderPrimaryText(context)),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: accent),
      floatingLabelStyle: TextStyle(color: accent),
      prefixIcon: Icon(icon, color: accent),
      filled: true,
      fillColor: fieldSurface,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
    ),
  );
}
