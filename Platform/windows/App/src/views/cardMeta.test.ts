// 卡片元信息的**纯函数判据**（`FR-R-13-08` 判据① 的「生成时间」与封面的 MIME）。
//
// 时间那一串退化形状全在这里钉住：换一台机器（不同时区）跑出来的数字必须一样，
// 所以判据直接断言「按包里写的墙上时间显示」，而不是 `toLocaleString()` 之类的本地化结果。
import { describe, expect, it } from 'vitest'
// 本文件放在 `views/`（不在插件目录里）：插件目录的判据 `check-plugins.mjs` 不许 import `vitest`，
// 而纯函数测试必须在仓里跑得动 ⇒ 测试住宿主侧，被测函数住插件侧，判据一条不放宽。
import { coverMime, formatGeneratedAt } from '../plugins/retro/cardMeta'

describe('formatGeneratedAt 生成时间', () => {
  it('an_iso_time_with_an_offset_keeps_the_wall_clock_it_was_written_with', () => {
    // +08:00 的 09:30 就显示 09:30 —— 不按读者所在时区再转一次
    expect(formatGeneratedAt('2026-10-18T09:30:00+08:00')).toBe('2026-10-18 09:30')
  })

  it('milliseconds_and_a_utc_z_suffix_are_trimmed_the_same_way', () => {
    expect(formatGeneratedAt('2026-10-18T09:30:12.345Z')).toBe('2026-10-18 09:30')
  })

  it('a_space_separated_time_is_accepted_too', () => {
    expect(formatGeneratedAt('2026-10-18 09:30')).toBe('2026-10-18 09:30')
  })

  it('a_date_without_a_time_stays_a_date_instead_of_inventing_midnight', () => {
    expect(formatGeneratedAt('2026-10-18')).toBe('2026-10-18')
  })

  it('an_empty_string_stays_empty_so_the_caller_can_say_not_stated', () => {
    expect(formatGeneratedAt('')).toBe('')
    expect(formatGeneratedAt('   ')).toBe('')
  })

  it('an_unrecognised_shape_is_shown_as_written_not_guessed', () => {
    // 生成侧写了奇怪形状 ⇒ 原样转述（宁可难看，不可编一个时间）
    expect(formatGeneratedAt('  上周三下午  ')).toBe('上周三下午')
  })
})

describe('coverMime 封面 MIME', () => {
  it('known_image_extensions_map_to_their_mime', () => {
    expect(coverMime('assets/cover.png')).toBe('image/png')
    expect(coverMime('assets/cover.webp')).toBe('image/webp')
    expect(coverMime('assets/cover.gif')).toBe('image/gif')
  })

  it('the_extension_is_matched_case_insensitively', () => {
    expect(coverMime('assets/COVER.JPG')).toBe('image/jpeg')
    expect(coverMime('assets/cover.jpeg')).toBe('image/jpeg')
  })

  it('an_unknown_or_missing_extension_falls_back_to_octet_stream', () => {
    expect(coverMime('assets/cover.bmp')).toBe('application/octet-stream')
    expect(coverMime('assets/cover')).toBe('application/octet-stream')
  })
})
