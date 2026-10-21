import itertools

import pytest

from app.bookings.state_machine import (
    ACTIVE_STATUSES,
    TERMINAL_STATUSES,
    TRANSITIONS,
    BookingEvent as E,
    BookingStatus as S,
    InvalidTransition,
    can_apply,
    is_terminal,
    next_status,
)

# Restated independently of TRANSITIONS from DESIGN.md §3, so a change to the
# table has to be made in both places on purpose.
EXPECTED: dict[tuple[S, E], S] = {
    (S.REQUESTED, E.START_MATCHING): S.MATCHING,
    (S.REQUESTED, E.CANCEL): S.CANCELLED,
    (S.REQUESTED, E.EXPIRE): S.EXPIRED,
    (S.MATCHING, E.MATCH_FOUND): S.CONFIRMED,
    (S.MATCHING, E.MATCH_FAILED): S.FAILED,
    (S.MATCHING, E.CANCEL): S.CANCELLED,
    (S.MATCHING, E.EXPIRE): S.EXPIRED,
    (S.CONFIRMED, E.FEEDER_APPROACHING): S.FEEDER_ARRIVING,
    (S.CONFIRMED, E.CANCEL): S.CANCELLED,
    (S.CONFIRMED, E.DRIVER_DEPARTED_PICKUP): S.NO_SHOW,
    (S.CONFIRMED, E.EXPIRE): S.EXPIRED,
    (S.FEEDER_ARRIVING, E.PASSENGER_BOARDED): S.BOARDED,
    (S.FEEDER_ARRIVING, E.CANCEL): S.CANCELLED,
    (S.FEEDER_ARRIVING, E.DRIVER_DEPARTED_PICKUP): S.NO_SHOW,
    (S.BOARDED, E.DRIVER_ARRIVED_DROPOFF): S.COMPLETED,
}

ALL_PAIRS = list(itertools.product(S, E))
VALID_PAIRS = [pair for pair in ALL_PAIRS if pair in EXPECTED]
INVALID_PAIRS = [pair for pair in ALL_PAIRS if pair not in EXPECTED]


def test_table_matches_design() -> None:
    assert TRANSITIONS == EXPECTED


@pytest.mark.parametrize(("status", "event"), VALID_PAIRS, ids=lambda v: v.value)
def test_valid_transition(status: S, event: E) -> None:
    assert can_apply(status, event)
    assert next_status(status, event) is EXPECTED[(status, event)]


@pytest.mark.parametrize(("status", "event"), INVALID_PAIRS, ids=lambda v: v.value)
def test_invalid_transition_raises_typed_error(status: S, event: E) -> None:
    assert not can_apply(status, event)
    with pytest.raises(InvalidTransition) as exc_info:
        next_status(status, event)
    assert exc_info.value.status is status
    assert exc_info.value.event is event
    assert exc_info.value.code == "invalid_transition"


def test_every_pair_is_covered() -> None:
    assert len(VALID_PAIRS) + len(INVALID_PAIRS) == len(S) * len(E)
    assert len(VALID_PAIRS) == len(EXPECTED)


def test_terminal_and_active_partition_all_statuses() -> None:
    assert TERMINAL_STATUSES == {S.COMPLETED, S.CANCELLED, S.FAILED, S.NO_SHOW, S.EXPIRED}
    assert ACTIVE_STATUSES == {S.REQUESTED, S.MATCHING, S.CONFIRMED, S.FEEDER_ARRIVING, S.BOARDED}
    assert TERMINAL_STATUSES.isdisjoint(ACTIVE_STATUSES)
    assert TERMINAL_STATUSES | ACTIVE_STATUSES == set(S)


@pytest.mark.parametrize("status", sorted(TERMINAL_STATUSES), ids=lambda v: v.value)
def test_terminal_statuses_have_no_outgoing_transitions(status: S) -> None:
    assert is_terminal(status)
    assert not any(can_apply(status, event) for event in E)


@pytest.mark.parametrize("status", sorted(ACTIVE_STATUSES), ids=lambda v: v.value)
def test_active_statuses_can_always_progress(status: S) -> None:
    assert not is_terminal(status)
    assert any(can_apply(status, event) for event in E)


def test_cancel_allowed_until_boarded_only() -> None:
    cancellable = {status for status in S if can_apply(status, E.CANCEL)}
    assert cancellable == {S.REQUESTED, S.MATCHING, S.CONFIRMED, S.FEEDER_ARRIVING}


def test_no_show_only_from_waiting_at_pickup() -> None:
    sources = {status for (status, _), target in TRANSITIONS.items() if target is S.NO_SHOW}
    assert sources == {S.CONFIRMED, S.FEEDER_ARRIVING}


def test_happy_path_reaches_completed() -> None:
    status = S.REQUESTED
    for event in (
        E.START_MATCHING,
        E.MATCH_FOUND,
        E.FEEDER_APPROACHING,
        E.PASSENGER_BOARDED,
        E.DRIVER_ARRIVED_DROPOFF,
    ):
        status = next_status(status, event)
    assert status is S.COMPLETED


def test_every_status_reachable_from_requested() -> None:
    reachable = {S.REQUESTED}
    frontier = [S.REQUESTED]
    while frontier:
        current = frontier.pop()
        for (source, _), target in TRANSITIONS.items():
            if source is current and target not in reachable:
                reachable.add(target)
                frontier.append(target)
    assert reachable == set(S)
