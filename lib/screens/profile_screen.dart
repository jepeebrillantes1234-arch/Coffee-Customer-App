import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/cart.dart';
import '../state/favorites.dart';
import '../state/nav.dart';
import 'addresses_screen.dart';
import 'auth_screen.dart';
import 'favorites_screen.dart';
import 'notifications_screen.dart';
import 'customer_service_sheet.dart';
import 'edit_profile_screen.dart';
import 'membership_screen.dart';
import 'payment_methods_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Widget _avatarButton({double size = 116}) {
    final url = (Api.I.user?['avatar_url'] ?? '').toString();
    return InkWell(
      onTap: _openEditProfile,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .16),
                      width: 5,
                    ),
                  ),
                  child: ClipOval(
                    child: url.isEmpty
                        ? ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Icon(
                              Icons.person,
                              color: Theme.of(context).colorScheme.primary,
                              size: size * .48,
                            ),
                          )
                        : NetImage(url, width: size, height: size),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 3,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.edit_rounded,
                  size: 19,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditProfile() async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const EditProfileScreen()));
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      final updated = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          var saving = false;
          var hideCurrent = true;
          var hideNext = true;
          var hideConfirm = true;
          String? serverError;
          return StatefulBuilder(
            builder: (ctx, dialogSetState) => Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 460,
                  maxHeight: 680,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(
                                Icons.lock_reset_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 13),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Change password',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Choose a strong password for your account.',
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(ctx, false),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _passwordInput(
                          controller: current,
                          label: 'Current password',
                          hidden: hideCurrent,
                          onToggle: () =>
                              dialogSetState(() => hideCurrent = !hideCurrent),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your current password.'
                              : null,
                        ),
                        const SizedBox(height: 15),
                        _passwordInput(
                          controller: next,
                          label: 'New password',
                          helper: 'Use at least 8 characters.',
                          hidden: hideNext,
                          onToggle: () =>
                              dialogSetState(() => hideNext = !hideNext),
                          validator: (value) {
                            if (value == null || value.length < 8) {
                              return 'Use at least 8 characters.';
                            }
                            if (value == current.text) {
                              return 'Choose a password different from your current one.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 15),
                        _passwordInput(
                          controller: confirm,
                          label: 'Confirm new password',
                          hidden: hideConfirm,
                          onToggle: () =>
                              dialogSetState(() => hideConfirm = !hideConfirm),
                          validator: (value) => value != next.text
                              ? 'The passwords do not match.'
                              : null,
                        ),
                        if (serverError != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              serverError!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.pop(ctx, false),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        if (!(formKey.currentState
                                                ?.validate() ??
                                            false)) {
                                          return;
                                        }
                                        dialogSetState(() {
                                          saving = true;
                                          serverError = null;
                                        });
                                        try {
                                          await Api.I.changePassword(
                                            currentPassword: current.text,
                                            password: next.text,
                                            passwordConfirmation: confirm.text,
                                          );
                                          if (ctx.mounted) {
                                            Navigator.pop(ctx, true);
                                          }
                                        } on ApiException catch (error) {
                                          if (ctx.mounted) {
                                            dialogSetState(() {
                                              saving = false;
                                              serverError = error.message;
                                            });
                                          }
                                        } catch (_) {
                                          if (ctx.mounted) {
                                            dialogSetState(() {
                                              saving = false;
                                              serverError = 'Could not update your password. Please try again.';
                                            });
                                          }
                                        }
                                      },
                                icon: saving
                                    ? const SizedBox.square(
                                        dimension: 17,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: Text(
                                  saving ? 'Updating…' : 'Update password',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      if (updated == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully.')),
        );
      }
    } finally {
      current.dispose();
      next.dispose();
      confirm.dispose();
    }
  }

  Widget _passwordInput({
    required TextEditingController controller,
    required String label,
    required bool hidden,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    String? helper,
  }) => TextFormField(
    controller: controller,
    obscureText: hidden,
    enableSuggestions: false,
    autocorrect: false,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show password' : 'Hide password',
        onPressed: onToggle,
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: validator,
  );

  Future<void> _deleteAccount() async {
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your account will be deleted and you will lose access to it.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Enter your password to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      password.dispose();
      return;
    }
    try {
      await Api.I.deleteAccount(password.text);
      Cart.I.clear();
      Favorites.I.clear();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (_) => false,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      password.dispose();
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var loggingOut = false;
        return StatefulBuilder(
          builder: (ctx, dialogSetState) => PopScope<bool>(
            canPop: !loggingOut,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.logout_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 27,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Log out?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Are you sure you want to logout? You will need to log in again to access your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: loggingOut
                            ? null
                            : () async {
                                dialogSetState(() => loggingOut = true);
                                await Api.I.logout();
                                Cart.I.clear();
                                Favorites.I.clear();
                                if (ctx.mounted) Navigator.pop(ctx, true);
                              },
                        icon: loggingOut
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.logout_rounded),
                        label: Text(
                          loggingOut ? 'Logging out…' : 'Yes, Logout',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: loggingOut
                            ? null
                            : () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Stay Logged In'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (confirmed != true) return;
    rootTab.value = 0;
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _openSettings() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, sheetSetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change password'),
                onTap: () => Navigator.pop(context, 'password'),
              ),
              SwitchListTile.adaptive(
                secondary: Icon(
                  AppThemeController.I.mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                ),
                title: const Text('Dark mode'),
                value: AppThemeController.I.mode == ThemeMode.dark,
                onChanged: (enabled) async {
                  await AppThemeController.I.setMode(
                    enabled ? ThemeMode.dark : ThemeMode.light,
                  );
                  sheetSetState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete account',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'password') await _changePassword();
    if (action == 'delete') await _deleteAccount();
  }

  void _openPaymentInfo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PaymentMethodsScreen()),
    );
  }

  void _openHelp() => showCustomerServiceSheet(context);

  void _openAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'KJM Coffee Shop',
      applicationIcon: Icon(
        Icons.coffee_rounded,
        color: Theme.of(context).colorScheme.primary,
        size: 36,
      ),
      applicationLegalese: 'Customer app',
    );
  }

  Widget _profileRow(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Icon(icon, color: colors.primary, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 25,
                color: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = Api.I.user ?? {};
    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 26),
            child: Row(
              children: [
                _avatarButton(size: 118),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${u['name'] ?? 'Customer'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 23,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Customer account',
                        style: TextStyle(
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit profile',
                  onPressed: _openEditProfile,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary
                        .withValues(alpha: .08),
                    minimumSize: const Size(54, 54),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 25),
                ),
              ],
            ),
          ),
          Column(
            children: [
              _profileRow(
                context,
                Icons.card_membership_rounded,
                'Membership & Rewards',
                () => open(const MembershipScreen()),
              ),
              const Divider(height: 1, indent: 74),
              _profileRow(
                context,
                Icons.receipt_long_outlined,
                'My Orders',
                () => rootTab.value = 3,
              ),
              const Divider(height: 1, indent: 74),
              _profileRow(
                context,
                Icons.location_on_outlined,
                'Addresses',
                () => open(const AddressesScreen()),
              ),
              const Divider(height: 1, indent: 74),
              _profileRow(
                context,
                Icons.credit_card_outlined,
                'Payment Methods',
                _openPaymentInfo,
              ),
              const Divider(height: 1, indent: 74),
              _profileRow(
                context,
                Icons.favorite_border_rounded,
                'Favorites',
                () => open(const FavoritesScreen()),
              ),
              const Divider(height: 1, indent: 74),
              _profileRow(
                context,
                Icons.notifications_none_rounded,
                'Notifications',
                () => open(const NotificationsScreen()),
              ),
              const Divider(height: 1, indent: 74),
              _profileRow(
                context,
                Icons.help_outline_rounded,
                'Help & Support',
                _openHelp,
              ),
              const Divider(height: 1, indent: 74),
              _profileRow(
                context,
                Icons.info_outline_rounded,
                'About',
                _openAbout,
              ),
              const Divider(height: 1, indent: 74),
              _profileRow(context, Icons.logout_rounded, 'Log out', _logout),
            ],
          ),
        ],
      ),
    );
  }
}
