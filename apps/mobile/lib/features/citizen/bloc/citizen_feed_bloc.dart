import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

part 'citizen_feed_event.dart';
part 'citizen_feed_state.dart';

class CitizenFeedBloc extends Bloc<CitizenFeedEvent, CitizenFeedState> {
  CitizenFeedBloc() : super(CitizenFeedInitial()) {
    on<CitizenFeedEvent>((event, emit) {
      // TODO: implement event handler
    });
  }
}
