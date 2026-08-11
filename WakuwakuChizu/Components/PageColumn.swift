import SwiftUI

extension View {
    /// Holds a screen's one column to the width the portrait design was tuned
    /// for, and centres it in whatever is left.
    ///
    /// Every screen here is a single column, laid out for a device held
    /// upright. The iPad also runs sideways — not by choice but because the
    /// App Store requires all four orientations of an iPad app (project.yml) —
    /// and a column that simply stretches into that width turns every stage
    /// card into a ribbon and every panel into a banner. Rather than keep a
    /// second, wide layout for each screen in step with the first, the column
    /// keeps its portrait width and the album page shows on either side:
    /// turning the device changes what surrounds the page, never the size of
    /// anything on it.
    ///
    /// 700pt is wider than any iPhone, so phones are untouched; it is the big
    /// iPads, in either orientation, whose columns it reins in.
    func pageColumn() -> some View {
        frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
    }
}
