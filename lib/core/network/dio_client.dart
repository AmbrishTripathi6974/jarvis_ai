import 'package:dio/dio.dart';

class DioClient {
  const DioClient(this._dio);

  final Dio _dio;

  Future<Response<ResponseBody>> postStream({
    required Uri uri,
    required Map<String, dynamic> data,
    Map<String, Object?>? headers,
  }) {
    return _dio.postUri<ResponseBody>(
      uri,
      data: data,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        contentType: Headers.jsonContentType,
      ),
    );
  }
}
