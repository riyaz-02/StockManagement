<?php
declare(strict_types=1);

namespace Portal\Support;

/** Indian money and number formatting (1,23,456.00), the same as the app. */
final class Money
{
    public static function inr(float|int|string|null $v, int $decimals = 2, bool $symbol = true): string
    {
        $n = round((float) $v, $decimals);
        $neg = $n < 0;
        $s = number_format(abs($n), $decimals, '.', '');
        [$int, $dec] = array_pad(explode('.', $s, 2), 2, '');
        $last3 = substr($int, -3);
        $rest = substr($int, 0, -3);
        if ($rest !== '') {
            $rest = preg_replace('/\B(?=(\d{2})+(?!\d))/', ',', $rest);
            $int = $rest . ',' . $last3;
        }
        return ($neg ? '-' : '') . ($symbol ? "\u{20B9}" : '') . $int . ($decimals > 0 ? '.' . $dec : '');
    }

    /** Weight in grams, up to 3 decimals, no trailing zeros. */
    public static function grams(float|int|string|null $v): string
    {
        $s = rtrim(rtrim(number_format((float) $v, 3, '.', ''), '0'), '.');
        return ($s === '' ? '0' : $s) . ' g';
    }

    /** 1536 -> "1.5 KB". Unknown (null) shows a dash. */
    public static function bytes(float|int|string|null $v): string
    {
        if ($v === null || $v === '') {
            return '–';
        }
        $n = (float) $v;
        foreach (['B', 'KB', 'MB', 'GB'] as $i => $unit) {
            if ($n < 1024 || $unit === 'GB') {
                return ($i === 0 ? (string) (int) $n : number_format($n, $n < 10 ? 1 : 0, '.', '')) . ' ' . $unit;
            }
            $n /= 1024;
        }
        return '';
    }
}
