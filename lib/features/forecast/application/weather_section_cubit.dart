import 'package:flutter_bloc/flutter_bloc.dart';

enum WeatherSection { graph, radar, forecast }

final class WeatherSectionCubit extends Cubit<WeatherSection> {
  WeatherSectionCubit({WeatherSection initialSection = WeatherSection.graph})
    : super(initialSection);

  void select(WeatherSection section) => emit(section);
}
