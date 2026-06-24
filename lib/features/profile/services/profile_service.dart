import '../../../core/api_service.dart';
import '../../../core/storage/token_storage.dart';
import '../models/company_model.dart';
import '../models/client_profile_model.dart';
import '../models/client_category_model.dart';
import '../models/client_company_detail_model.dart';
import '../models/credit_model.dart';
import '../models/notification_model.dart';

class ProfileService {
  final ApiService _apiService;
  final TokenStorage _tokenStorage;

  ProfileService({
    ApiService? apiService,
    TokenStorage? tokenStorage,
  })  : _apiService = apiService ?? ApiService(),
        _tokenStorage = tokenStorage ?? TokenStorage();

  TokenStorage get tokenStorage => _tokenStorage;

  Future<List<Company>> getMyCompanies() async {
    final response = await _apiService.get('/api/empresas/mis-empresas');
    if (response is List) {
      return response.map((json) => Company.fromJson(json as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<ClientProfile>> getMyClientProfiles(int userId) async {
    final response = await _apiService.get('/api/clientes/$userId');
    if (response is List) {
      return response.map((json) => ClientProfile.fromJson(json as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<ClientCategory> getCategory(int companyId, int categoryId) async {
    final response = await _apiService.get('/api/categorias-cliente/$companyId/$categoryId');
    if (response is Map<String, dynamic>) {
      return ClientCategory.fromJson(response);
    }
    throw const ApiException('Respuesta de categoría inválida del servidor');
  }

  Future<ClientCompanyDetail?> getClientDetail(int companyId, int userId) async {
    final response = await _apiService.get('/api/empresas/$companyId/clientes');
    if (response is List) {
      final list = response.map((json) => ClientCompanyDetail.fromJson(json as Map<String, dynamic>)).toList();
      for (final detail in list) {
        if (detail.idUsuario == userId) {
          return detail;
        }
      }
    }
    return null;
  }

  Future<List<AccountReceivable>> getClientCredits(int companyId, int clientId) async {
    final response = await _apiService.get('/api/empresas/$companyId/clientes/$clientId/cuentas-por-cobrar');
    if (response is List) {
      return response.map((json) => AccountReceivable.fromJson(json as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<NotificationModel>> getNotifications(int companyId) async {
    final response = await _apiService.get('/notifications/history/empresas/$companyId');
    if (response is Map<String, dynamic> && response['items'] is List) {
      final items = response['items'] as List;
      final list = items.map((json) => NotificationModel.fromJson(json as Map<String, dynamic>)).toList();
      // Sort newest first
      list.sort((a, b) => b.fecha.compareTo(a.fecha));
      return list;
    }
    return [];
  }

  Future<bool> markNotificationAsRead(int notificationId) async {
    try {
      final response = await _apiService.post('/notifications/mark-read', {'id': notificationId});
      if (response is Map<String, dynamic> && response['ok'] == true) {
        return true;
      }
    } catch (_) {}
    return false;
  }
}

