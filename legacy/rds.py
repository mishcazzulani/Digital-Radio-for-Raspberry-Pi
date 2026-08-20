"""RDS decoder for the Si468x FM_RDS_STATUS (empirically verified on-air).

The Si468x chip reports RDS characters already decoded as 8-bit ASCII
bytes packed inside the 16-bit blocks (verified live on 102.5 RTL 102.5,
PI=0x5218):

  Group 0A (PS): block D carries 2 chars as bytes; the PS segment is in
                  block B bits 1-0 (verified: 30/30/29/30 samples per
                  segment on 102.5 -> "RTL102.5", no rotation needed).
  Group 2A (RT): 4 chars per group (2 from block C bytes + 2 from block D
                  bytes); the RT segment is the LOW NIBBLE of block B
                  (verified on 98.4: B=0x2520..0x252d = segments 0..13);
                  reset the accumulator when segment 0 changes (RT text
                  change).
  Group A    : PI code (block A).

No 6-bit charset decoding is needed: the bytes are already ASCII.
"""


_PTY_NAMES = [
    "No programme type", "News", "Current affairs", "Information", "Sport",
    "Education", "Drama", "Culture", "Science", "Varied", "Pop music",
    "Rock music", "Easy listening", "Light classics", "Serious classics",
    "Other music", "Weather", "Finance", "Children's", "Social affairs",
    "Religion", "Phone-in", "Travel", "Leisure", "Jazz music", "Country music",
    "National music", "Oldies music", "Folk music", "Documentary", "Alarm test",
    "Alarm",
]


class RdsDecoder:
    """Accumulates PS/RT from RDS groups; safe to call from one thread."""

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.ps = ""
        self.rt = ""
        self.pi: int | None = None
        self.pty: int | None = None
        self.pty_name = ""
        self.has_ps = False
        self.has_rt = False
        self.updated_at: float | None = None
        self._ps_seg: list[str] = ["", ""]
        self._ps_pos = 0
        self._rt_seg: dict[int, str] = {}

    @staticmethod
    def _char(v: int) -> str:
        if 0x20 <= v <= 0x7E:
            return chr(v)
        return " "

    def feed(self, blocks: dict, pi: int | None = None, ts: float | None = None) -> None:
        bler = blocks.get("bler") or {}
        if bler.get("b", 0) > 0 or bler.get("c", 0) > 0 or bler.get("d", 0) > 0:
            return  # segment (B) or char blocks (C/D) errored -> skip group
        a = int(blocks.get("a") or 0)
        b = int(blocks.get("b") or 0)
        c = int(blocks.get("c") or 0)
        d = int(blocks.get("d") or 0)
        if a:
            self.pi = a if pi is None else pi
        group = (b >> 12) & 0x0F
        if (b >> 11) & 0x01:
            group += 8
        self.pty = (b >> 5) & 0x1F
        self.pty_name = _PTY_NAMES[self.pty] if 0 <= self.pty < len(_PTY_NAMES) else ""
        if ts is None:
            import time
            ts = time.time()

        if group == 0:                     # 0A: PS — segment = B bits 1-0
            seg = b & 0x03
            ch1 = self._char((d >> 8) & 0xFF)
            ch2 = self._char(d & 0xFF)
            if ch1 != " " or ch2 != " ":
                s = list(self.ps.ljust(8, " "))
                s[seg * 2] = ch1
                s[seg * 2 + 1] = ch2
                self.ps = "".join(s)
                self.has_ps = True
                self.updated_at = ts
        elif group == 2:                   # 2A: RadioText (4 chars per group)
            addr = b & 0x0F               # segment = low nibble of block B
            chars = "".join(
                self._char(v) for v in (
                    (c >> 8) & 0xFF, c & 0xFF,
                    (d >> 8) & 0xFF, d & 0xFF,
                ))
            if chars.strip():
                if addr == 0:
                    old = self._rt_seg.get(0)
                    if old is not None and old != chars:
                        self._rt_seg.clear()   # station changed the RT text
                self._rt_seg[addr] = chars
                parts = []
                start = min(self._rt_seg) if self._rt_seg else 0
                for i in range(start, 16):
                    seg = self._rt_seg.get(i)
                    if seg is None or not seg.strip():
                        break   # missing segment or padding -> stop
                    parts.append(seg)
                self.rt = "".join(parts).rstrip()
                self.has_rt = bool(self.rt)
                self.updated_at = ts

    def state(self) -> dict:
        return {
            "ps": self.ps,
            "rt": self.rt,
            "pi": self.pi,
            "pty": self.pty,
            "pty_name": self.pty_name,
            "has_ps": self.has_ps,
            "has_rt": self.has_rt,
            "updated_at": self.updated_at,
        }
