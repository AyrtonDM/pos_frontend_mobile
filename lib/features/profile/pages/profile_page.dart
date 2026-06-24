import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/constants/app_palette.dart';
import '../../../core/utils/jwt_decoder.dart';
import '../../../shared/widgets/side_menu_scaffold.dart';
import '../models/client_category_model.dart';
import '../models/client_company_detail_model.dart';
import '../models/client_profile_model.dart';
import '../models/company_model.dart';
import '../models/notification_model.dart';
import '../services/profile_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _profileService = ProfileService();
  bool _isLoading = true;
  String? _errorMessage;

  // Logged in user info
  int? _userId;
  String? _userEmail;

  // Loaded data
  List<Company> _companies = [];
  List<ClientProfile> _clientProfiles = [];
  List<NotificationModel> _notifications = [];
  
  // Selected company and corresponding profiles
  Company? _selectedCompany;
  ClientProfile? _selectedProfile;
  ClientCategory? _selectedCategory;
  ClientCompanyDetail? _companyDetail;

  // Navigation menu state
  int _currentSectionIndex = 0; // 0 = Home, 1 = Credits, 2 = Notifications

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await _profileService.tokenStorage.getToken();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRouter.login);
        return;
      }

      final userIdStr = JwtDecoder.getUserId(token);
      final email = JwtDecoder.getEmail(token);

      if (userIdStr == null) {
        throw Exception('Token inválido: No se pudo extraer el ID de usuario.');
      }

      _userId = int.parse(userIdStr);
      _userEmail = email;

      // Fetch companies and client profiles in parallel
      final results = await Future.wait([
        _profileService.getMyCompanies(),
        _profileService.getMyClientProfiles(_userId!),
      ]);

      _companies = results[0] as List<Company>;
      _clientProfiles = results[1] as List<ClientProfile>;

      if (_companies.isNotEmpty && _clientProfiles.isNotEmpty) {
        // Find first company that also has a client profile
        for (final company in _companies) {
          final profile = _clientProfiles.firstWhere(
            (p) => p.idUsuario == _userId,
            orElse: () => const ClientProfile(
              idCliente: 0,
              idUsuario: 0,
              codigoCliente: '',
              saldoCredito: 0,
              limiteCredito: 0,
              activo: false,
            ),
          );

          if (profile.idCliente != 0) {
            _selectedCompany = company;
            _selectedProfile = profile;
            break;
          }
        }

        // If no matching profile was found, default to first of each (fallback)
        _selectedCompany ??= _companies.first;
        _selectedProfile ??= _clientProfiles.first;

        await _loadSelectedCompanyDetails();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSelectedCompanyDetails() async {
    if (_selectedCompany == null || _userId == null) return;

    try {
      setState(() {
        _isLoading = true;
      });

      // 1. Fetch detailed profile info of client within this company (gets persona details)
      _companyDetail = await _profileService.getClientDetail(
        _selectedCompany!.idEmpresa,
        _userId!,
      );

      // If the company detail returns a client profile, override our selected profile
      if (_companyDetail?.cliente != null) {
        _selectedProfile = _companyDetail!.cliente;
      }

      // 2. Fetch category details if category ID exists
      if (_selectedProfile?.idCategoriaCliente != null) {
        _selectedCategory = await _profileService.getCategory(
          _selectedCompany!.idEmpresa,
          _selectedProfile!.idCategoriaCliente!,
        );
      } else {
        _selectedCategory = null;
      }

      // 3. Populate mock notifications (local demonstration as requested)
      _notifications = [
        NotificationModel(
          id: 1,
          prioridad: 1,
          tipo: 'CREDITO',
          titulo: 'Línea de crédito aprobada',
          mensaje: 'Tu línea de crédito ha sido habilitada en ${_selectedCompany!.nombre}.',
          leido: false,
          fecha: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        NotificationModel(
          id: 2,
          prioridad: 0,
          tipo: 'GENERAL',
          titulo: 'Bienvenido a la aplicación',
          mensaje: 'Ya puedes realizar el seguimiento de tus créditos e historial de abonos.',
          leido: false,
          fecha: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar detalles de la empresa: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _onCompanyChanged(Company? newCompany) async {
    if (newCompany == null || newCompany.idEmpresa == _selectedCompany?.idEmpresa) return;

    setState(() {
      _selectedCompany = newCompany;
      // Find matching client profile
      _selectedProfile = _clientProfiles.firstWhere(
        (p) => p.idUsuario == _userId,
        orElse: () => _clientProfiles.first,
      );
    });

    await _loadSelectedCompanyDetails();
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que deseas salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _profileService.tokenStorage.clearToken();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRouter.login);
    }
  }

  void _markAsRead(NotificationModel notification) {
    if (notification.leido) return;

    setState(() {
      final index = _notifications.indexWhere((n) => n.id == notification.id);
      if (index != -1) {
        _notifications[index] = NotificationModel(
          id: notification.id,
          idEmpresa: notification.idEmpresa,
          prioridad: notification.prioridad,
          tipo: notification.tipo,
          titulo: notification.titulo,
          mensaje: notification.mensaje,
          payload: notification.payload,
          leido: true,
          fecha: notification.fecha,
        );
      }
    });
  }

  int get _unreadCount {
    return _notifications.where((n) => !n.leido).length;
  }

  @override
  Widget build(BuildContext context) {
    final persona = _companyDetail?.usuario.persona;
    final String userName = persona?.nombreCompleto ?? 'Cliente POS';
    final String userEmail = _userEmail ?? '';

    String appBarTitle = 'Mi Perfil de Cliente';
    if (_currentSectionIndex == 1) {
      appBarTitle = 'Gestión de Créditos';
    } else if (_currentSectionIndex == 2) {
      appBarTitle = 'Notificaciones';
    }

    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        title: Text(appBarTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      drawer: _isLoading || _companies.isEmpty || _selectedProfile == null
          ? null
          : ClientDrawer(
              userName: userName,
              userEmail: userEmail,
              currentSectionIndex: _currentSectionIndex,
              unreadNotificationsCount: _unreadCount,
              onSectionSelected: (index) {
                setState(() {
                  _currentSectionIndex = index;
                });
                Navigator.of(context).pop(); // Close drawer
              },
              onLogout: _logout,
            ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppPalette.primary,
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      color: AppPalette.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: AppPalette.danger, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppPalette.text, fontSize: 16),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _loadInitialData,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _companies.isEmpty || _selectedProfile == null
                    ? Center(
                        child: Card(
                          margin: const EdgeInsets.all(24),
                          color: AppPalette.surface,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_off_outlined, color: AppPalette.textSoft, size: 56),
                                const SizedBox(height: 16),
                                const Text(
                                  'Sin Perfil de Cliente',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'No estás registrado como cliente activo en ninguna empresa del sistema POS.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppPalette.textSoft),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: _logout,
                                  child: const Text('Cerrar Sesión'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildActiveSection(persona),
                      ),
      ),
    );
  }

  Widget _buildActiveSection(PersonaEmployee? persona) {
    switch (_currentSectionIndex) {
      case 0:
        return _buildPersonalCard(persona);
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Company Selector
            _buildCompanySelector(),
            const SizedBox(height: 16),

            // Credit Summary Card
            _buildCreditSummaryCard(),
            const SizedBox(height: 24),

            // Action Button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  AppRouter.credits,
                  arguments: {
                    'companyId': _selectedCompany!.idEmpresa,
                    'companyName': _selectedCompany!.nombre,
                    'clientId': _selectedProfile!.idCliente,
                  },
                );
              },
              icon: const Icon(Icons.account_balance_wallet_outlined, color: AppPalette.text),
              label: const Text('Ver historial de mis Créditos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: AppPalette.text,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      case 2:
        return _buildNotificationsSection();
      default:
        return _buildPersonalCard(persona);
    }
  }

  Widget _buildPersonalCard(PersonaEmployee? persona) {
    return Card(
      color: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.border),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppPalette.bgSoft,
                  radius: 28,
                  child: const Icon(Icons.person, color: AppPalette.text, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        persona?.nombreCompleto ?? 'Cliente POS',
                        style: const TextStyle(
                          color: AppPalette.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userEmail ?? '',
                        style: const TextStyle(
                          color: AppPalette.textSoft,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32, color: AppPalette.border),
            _buildDetailRow(Icons.badge_outlined, 'Documento', persona?.documento ?? '-'),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.phone_outlined, 'Teléfono', persona?.telefono ?? '-'),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.cake_outlined, 
              'Fecha de Nacimiento', 
              persona != null 
                  ? '${persona.fechaNacimiento.day.toString().padLeft(2, '0')}/${persona.fechaNacimiento.month.toString().padLeft(2, '0')}/${persona.fechaNacimiento.year}'
                  : '-'
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.wc_outlined, 
              'Género', 
              persona?.genero == 'M' 
                  ? 'Masculino' 
                  : persona?.genero == 'F' 
                      ? 'Femenino' 
                      : 'Otro'
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppPalette.textSoft),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: const TextStyle(color: AppPalette.textSoft, fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: AppPalette.text, fontWeight: FontWeight.bold),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildCompanySelector() {
    return Card(
      color: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.border),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.business, color: AppPalette.textSoft),
            const SizedBox(width: 12),
            const Text(
              'Empresa:',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppPalette.textSoft),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Company>(
                  value: _selectedCompany,
                  items: _companies.map((company) {
                    return DropdownMenuItem<Company>(
                      value: company,
                      child: Text(
                        company.nombre,
                        style: const TextStyle(
                          color: AppPalette.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: _onCompanyChanged,
                  icon: const Icon(Icons.keyboard_arrow_down, color: AppPalette.text),
                  dropdownColor: AppPalette.surface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditSummaryCard() {
    final double limit = _selectedProfile?.limiteCredito ?? 0.0;
    final double used = _selectedProfile?.saldoCredito ?? 0.0;
    final double available = (limit - used) > 0 ? (limit - used) : 0.0;

    final progress = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isLimitExceeded = used > limit;

    return Card(
      color: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.border),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.credit_card, color: AppPalette.primary, size: 24),
                SizedBox(width: 8),
                Text(
                  'Línea de Crédito',
                  style: TextStyle(
                    color: AppPalette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Progress bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: AppPalette.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isLimitExceeded 
                          ? AppPalette.danger 
                          : progress > 0.8 
                              ? AppPalette.warning 
                              : AppPalette.success
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Uso de línea de crédito: ${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12, 
                        color: isLimitExceeded ? AppPalette.danger : AppPalette.textSoft,
                        fontWeight: isLimitExceeded ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    Text(
                      'Cód: ${_selectedProfile?.codigoCliente ?? ''}',
                      style: const TextStyle(fontSize: 12, color: AppPalette.textSoft),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Financial breakdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFinancialItem(
                  'Límite', 
                  '\$${limit.toStringAsFixed(2)}', 
                  AppPalette.textSoft
                ),
                _buildFinancialItem(
                  'Utilizado', 
                  '\$${used.toStringAsFixed(2)}', 
                  isLimitExceeded ? AppPalette.danger : AppPalette.warning
                ),
                _buildFinancialItem(
                  'Disponible', 
                  '\$${available.toStringAsFixed(2)}', 
                  AppPalette.success
                ),
              ],
            ),

            const Divider(height: 32, color: AppPalette.border),

            // Category detail info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Categoría de Cliente', style: TextStyle(color: AppPalette.textSoft, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      _selectedCategory?.nombre ?? 'General',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Plazo de Pago', style: TextStyle(color: AppPalette.textSoft, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      _selectedCategory != null 
                          ? '${_selectedCategory!.plazoCredito} días' 
                          : 'N/A',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Descuento Base', style: TextStyle(color: AppPalette.textSoft, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      _selectedCategory != null 
                          ? '${(_selectedCategory!.descuentoBase * 100).toStringAsFixed(1)}%' 
                          : '0.0%',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Estado de Perfil', style: TextStyle(color: AppPalette.textSoft, fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (_selectedProfile?.activo ?? false) 
                            ? AppPalette.success.withValues(alpha: 0.1) 
                            : AppPalette.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (_selectedProfile?.activo ?? false) 
                              ? AppPalette.success.withValues(alpha: 0.5) 
                              : AppPalette.danger.withValues(alpha: 0.5)
                        ),
                      ),
                      child: Text(
                        (_selectedProfile?.activo ?? false) ? 'ACTIVO' : 'INACTIVO',
                        style: TextStyle(
                          color: (_selectedProfile?.activo ?? false) ? AppPalette.success : AppPalette.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialItem(String title, String amount, Color amountColor) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppPalette.textSoft,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          amount,
          style: TextStyle(
            color: amountColor,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsSection() {
    if (_notifications.isEmpty) {
      return Card(
        color: AppPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppPalette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 64,
                color: AppPalette.textSoft.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 16),
              const Text(
                'No tienes notificaciones',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppPalette.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Te mantendremos al tanto de cualquier novedad de ${_selectedCompany?.nombre ?? 'tu empresa'}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppPalette.textSoft, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.border),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined, color: AppPalette.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Historial de Alertas (${_notifications.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppPalette.text,
                      ),
                    ),
                  ],
                ),
                if (_unreadCount > 0)
                  Text(
                    '$_unreadCount pendientes',
                    style: const TextStyle(
                      color: AppPalette.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const Divider(height: 24, color: AppPalette.border),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _notifications.length,
              separatorBuilder: (context, index) => const Divider(height: 16, color: AppPalette.surface2),
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                final dateFormatted = _formatDateTime(notification.fecha);

                Color priorityColor = AppPalette.textSoft;
                if (notification.prioridad > 1) {
                  priorityColor = AppPalette.danger;
                } else if (notification.prioridad == 1) {
                  priorityColor = AppPalette.warning;
                }

                return InkWell(
                  onTap: () => _markAsRead(notification),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Unread indicator dot or Priority icon
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            notification.leido 
                                ? Icons.notifications_none 
                                : Icons.notifications_active,
                            color: notification.leido 
                                ? AppPalette.textSoft.withValues(alpha: 0.5) 
                                : AppPalette.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      notification.titulo,
                                      style: TextStyle(
                                        fontWeight: notification.leido 
                                            ? FontWeight.w600 
                                            : FontWeight.bold,
                                        fontSize: 14,
                                        color: notification.leido 
                                            ? AppPalette.text 
                                            : AppPalette.text,
                                      ),
                                    ),
                                  ),
                                  if (!notification.leido) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppPalette.info,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                notification.mensaje,
                                style: TextStyle(
                                  color: notification.leido 
                                      ? AppPalette.textSoft 
                                      : AppPalette.textSoft.withValues(alpha: 0.9),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    dateFormatted,
                                    style: const TextStyle(
                                      color: AppPalette.textSoft,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (notification.prioridad > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: priorityColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        notification.prioridad > 1 ? 'ALTA' : 'MEDIA',
                                        style: TextStyle(
                                          color: priorityColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
