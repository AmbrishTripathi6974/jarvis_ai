import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:isar/isar.dart';
import 'package:jarvis/core/network/connectivity_service.dart';
import 'package:jarvis/core/network/connectivity_cubit.dart';
import 'package:jarvis/core/network/dio_client.dart';
import 'package:jarvis/core/storage/image_storage.dart';
import 'package:jarvis/core/utils/constants.dart';
import 'package:jarvis/features/chat/data/datasources/chat_local_datasource.dart';
import 'package:jarvis/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:jarvis/features/chat/data/models/chat_message_model.dart';
import 'package:jarvis/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:jarvis/features/chat/domain/repositories/chat_repository.dart';
import 'package:jarvis/features/chat/domain/usecases/clear_chat.dart';
import 'package:jarvis/features/chat/domain/usecases/delete_messages_by_ids.dart';
import 'package:jarvis/features/chat/domain/usecases/get_chat_history.dart';
import 'package:jarvis/features/chat/domain/usecases/send_message.dart';
import 'package:jarvis/features/chat/domain/usecases/save_message.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:path_provider/path_provider.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  if (getIt.isRegistered<ChatBloc>()) {
    return;
  }

  final directory = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [ChatMessageModelSchema],
    directory: directory.path,
  );

  getIt
    ..registerLazySingleton<Connectivity>(() => Connectivity())
    ..registerLazySingleton(() => ConnectivityService(getIt<Connectivity>()))
    ..registerFactory(() => ConnectivityCubit(getIt<ConnectivityService>()))
    ..registerLazySingleton(() => ImageStorage())
    ..registerLazySingleton<Dio>(
      () => Dio(
        BaseOptions(
          connectTimeout: AppConstants.connectTimeout,
          receiveTimeout: AppConstants.receiveTimeout,
          sendTimeout: AppConstants.sendTimeout,
        ),
      ),
    )
    ..registerLazySingleton(() => DioClient(getIt<Dio>()))
    ..registerLazySingleton<Isar>(() => isar)
    ..registerLazySingleton<ChatRemoteDataSource>(
      () => ChatRemoteDataSourceImpl(getIt<DioClient>()),
    )
    ..registerLazySingleton<ChatLocalDataSource>(
      () => ChatLocalDataSourceImpl(getIt<Isar>()),
    )
    ..registerLazySingleton<ChatRepository>(
      () => ChatRepositoryImpl(
        getIt<ChatRemoteDataSource>(),
        getIt<ChatLocalDataSource>(),
      ),
    )
    ..registerLazySingleton(() => SendMessage(getIt<ChatRepository>()))
    ..registerLazySingleton(() => SaveMessage(getIt<ChatRepository>()))
    ..registerLazySingleton(() => DeleteMessagesByIds(getIt<ChatRepository>()))
    ..registerLazySingleton(() => GetChatHistory(getIt<ChatRepository>()))
    ..registerLazySingleton(() => ClearChat(getIt<ChatRepository>()))
    ..registerFactory(
      () => ChatBloc(
        getIt<SendMessage>(),
        getIt<SaveMessage>(),
        getIt<DeleteMessagesByIds>(),
        getIt<GetChatHistory>(),
        getIt<ClearChat>(),
        getIt<ConnectivityService>().isOnlineStream,
        getIt<ImageStorage>(),
      ),
    );
}
