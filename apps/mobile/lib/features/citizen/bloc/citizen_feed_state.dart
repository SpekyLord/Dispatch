part of 'citizen_feed_bloc.dart';

abstract class CitizenFeedState extends Equatable {
  const CitizenFeedState();

  @override
  List<Object> get props => [];
}

class CitizenFeedInitial extends CitizenFeedState {}
