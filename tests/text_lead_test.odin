package tests

import "core:testing"
import ui "../loom"

// A span's `lead` reserves blank width before its first byte, for a host that
// draws something of its own inside the line. The fake backend is ten pixels a
// rune, so every width below is exact.

@(private = "file")
GAP :: f32(14)

@(private = "file")
lead_row :: proc(spans: []ui.Text_Span, text := "abcd") -> ui.Interaction {
    return ui.leaf(
        {
            key = "row",
            text = text,
            spans = spans,
            props = {font_size = 16, text_wrap = .None, w = ui.FIT, h = ui.Px(20)},
        },
    )
}

@(private = "file")
lead_frames :: proc(spans: []ui.Text_Span, text := "abcd") -> ui.Interaction {
    it: ui.Interaction
    for _ in 0 ..< 2 {
        rig_open(&Rig{})
        it = lead_row(spans, text)
        ui.end_frame()
    }
    return it
}

@(test)
test_a_lead_widens_the_measured_line :: proc(t: ^testing.T) {
    ctx: ui.Context
    wired(&ctx)
    defer ui.destroy(&ctx)

    plain := []ui.Text_Span{{start = 2, end = 3, color = RED}}
    leaded := []ui.Text_Span{{start = 2, end = 3, color = RED, lead = GAP}}

    a := lead_frames(plain)
    testing.expect_value(t, a.rect.w, 4 * CHAR_W)

    b := lead_frames(leaded)
    testing.expect_value(t, b.rect.w, 4 * CHAR_W + GAP)
}

@(test)
test_a_lead_moves_the_runs_after_it :: proc(t: ^testing.T) {
    ctx: ui.Context
    wired(&ctx)
    defer ui.destroy(&ctx)

    spans := []ui.Text_Span{{start = 2, end = 3, color = RED, lead = GAP}}
    it := lead_frames(spans)

    runs := ui.text_runs(it.node)
    testing.expect_value(t, len(runs), 3)
    testing.expect_value(t, runs[0].text, "ab")
    testing.expect_value(t, runs[1].text, "c")
    testing.expect_value(t, runs[2].text, "d")
    testing.expect_value(t, runs[0].pos.x, f32(0))
    // The gap opens before "c", so it and everything after it sit past it.
    testing.expect_value(t, runs[1].pos.x - runs[0].pos.x, 2 * CHAR_W + GAP)
    testing.expect_value(t, runs[2].pos.x - runs[1].pos.x, CHAR_W)
}

@(test)
test_the_caret_counts_the_gaps_before_it :: proc(t: ^testing.T) {
    ctx: ui.Context
    wired(&ctx)
    defer ui.destroy(&ctx)

    spans := []ui.Text_Span{{start = 2, end = 3, color = RED, lead = GAP}}
    props := ui.Props{font_size = 16, text_wrap = .None}

    rig_open(&Rig{})
    testing.expect_value(t, ui.caret_x("abcd", 1, props, spans), CHAR_W)
    // At the anchor itself the caret is already past the gap, which is where the
    // host drew whatever it reserved the width for.
    testing.expect_value(t, ui.caret_x("abcd", 2, props, spans), 2 * CHAR_W + GAP)
    testing.expect_value(t, ui.caret_x("abcd", 4, props, spans), 4 * CHAR_W + GAP)
    // Without the spans the same text measures as it always did.
    testing.expect_value(t, ui.caret_x("abcd", 4, props), 4 * CHAR_W)
    ui.end_frame()
}

@(test)
test_the_hit_test_agrees_with_the_caret :: proc(t: ^testing.T) {
    ctx: ui.Context
    wired(&ctx)
    defer ui.destroy(&ctx)

    spans := []ui.Text_Span{{start = 2, end = 3, color = RED, lead = GAP}}
    props := ui.Props{font_size = 16, text_wrap = .None}

    rig_open(&Rig{})
    for at in ([]int{0, 1, 2, 3, 4}) {
        x := ui.caret_x("abcd", at, props, spans)
        testing.expectf(
            t,
            ui.offset_at("abcd", x, props, spans) == at,
            "x %v of byte %v resolves back to it",
            x,
            at,
        )
    }
    // An x inside the gap belongs to the byte the gap opens at.
    inside := 2 * CHAR_W + GAP * 0.5
    testing.expect_value(t, ui.offset_at("abcd", inside, props, spans), 2)
    ui.end_frame()
}

@(test)
test_a_lead_leaves_the_tab_grid_alone :: proc(t: ^testing.T) {
    ctx: ui.Context
    wired(&ctx)
    defer ui.destroy(&ctx)

    // "ab" ends at 20, the tab goes to the 40 stop, "x" follows it.
    spans := []ui.Text_Span{{start = 0, end = 1, color = RED, lead = GAP}}
    it: ui.Interaction
    for _ in 0 ..< 2 {
        rig_open(&Rig{})
        it = ui.leaf(
            {
                key = "row",
                text = "ab\tx",
                spans = spans,
                props = {
                    font_size = 16,
                    text_wrap = .None,
                    tab_size = TAB_W,
                    w = ui.FIT,
                    h = ui.Px(20),
                },
            },
        )
        ui.end_frame()
    }

    // The span ends inside "ab", so the colored byte is a run of its own.
    runs := ui.text_runs(it.node)
    testing.expect_value(t, len(runs), 3)
    testing.expect_value(t, runs[0].text, "a")
    testing.expect_value(t, runs[1].text, "b")
    testing.expect_value(t, runs[2].text, "x")
    // Everything shifts by the one gap, and the stop keeps its place in the line.
    testing.expect_value(t, runs[0].pos.x, GAP)
    testing.expect_value(t, runs[1].pos.x, CHAR_W + GAP)
    testing.expect_value(t, runs[2].pos.x, TAB_W + GAP)
}

@(test)
test_span_lead_before_is_what_a_host_adds :: proc(t: ^testing.T) {
    spans := []ui.Text_Span {
        {start = 2, end = 3, lead = GAP},
        {start = 5, end = 6, lead = GAP},
    }
    testing.expect_value(t, ui.span_lead_before(spans, 0), f32(0))
    testing.expect_value(t, ui.span_lead_before(spans, 1), f32(0))
    testing.expect_value(t, ui.span_lead_before(spans, 2), GAP)
    testing.expect_value(t, ui.span_lead_before(spans, 4), GAP)
    testing.expect_value(t, ui.span_lead_before(spans, 5), 2 * GAP)
    testing.expect_value(t, ui.span_lead_before(spans, 99), 2 * GAP)
}

// Two gap sets over one text are two layouts: the cache key carries the leads,
// or the second reads back the first's widths.
@(test)
test_the_text_cache_keys_on_the_gaps :: proc(t: ^testing.T) {
    ctx: ui.Context
    wired(&ctx)
    defer ui.destroy(&ctx)

    narrow := []ui.Text_Span{{start = 2, end = 3, color = RED, lead = GAP}}
    wide := []ui.Text_Span{{start = 2, end = 3, color = RED, lead = GAP * 3}}

    a := lead_frames(narrow)
    testing.expect_value(t, a.rect.w, 4 * CHAR_W + GAP)
    b := lead_frames(wide)
    testing.expect_value(t, b.rect.w, 4 * CHAR_W + GAP * 3)
    c := lead_frames(narrow)
    testing.expect_value(t, c.rect.w, 4 * CHAR_W + GAP)
}
