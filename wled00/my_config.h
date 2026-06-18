#pragma once

// Compatibility definitions for the current FX_fcn.cpp palette ID layout.
// These mirror upstream WLED's palette ID bases and keep builds working until
// const.h is brought fully in sync with upstream.
#ifndef WLED_USERMOD_PALETTE_ID_BASE
constexpr uint8_t WLED_USERMOD_PALETTE_ID_BASE = 255;
#endif
#ifndef WLED_CUSTOM_PALETTE_ID_BASE
constexpr uint8_t WLED_CUSTOM_PALETTE_ID_BASE = 200;
#endif
