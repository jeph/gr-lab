#!/usr/bin/env python3
"""The camera's menu text in every menu language, from its firmware.

    menu_strings.py RTOS_BIN            lists the English table with indexes
    menu_strings.py RTOS_BIN TERM       TERM in every language (exact match
                                        on the English, ignoring case)
    menu_strings.py RTOS_BIN --index N  entry N in every language

RTOS_BIN is the RTOS image of a firmware package, such as
`firmware/gr4_v120/rtos.bin` in the research workspace. How the tables are
laid out is in research/camera-menu-languages.md. The output is Ricoh's
text: use it to word GR Photo's translations as the camera does, and do not
commit it.
"""

import struct
import sys

ENGLISH = 'English'


def utf16(image, offset):
    end = offset
    while image[end:end + 2] != b'\0\0':
        end += 2
    return image[offset:end].decode('utf-16-le', errors='replace')


def find_all(image, needle):
    at = image.find(needle)
    while at != -1:
        yield at
        at = image.find(needle, at + 1)


def tables(image):
    """Every language's list of strings, in firmware order."""
    name = ENGLISH.encode('utf-16-le') + b'\0\0'
    # A record is {u32 tag, u32 address of the text}; the tag's low byte
    # is the length with the terminator, and the next byte the line count.
    tag = struct.pack('<I', 0x100 | (len(ENGLISH) + 1))
    for text in find_all(image, name):
        for record in find_all(image, tag):
            address = struct.unpack_from('<I', image, record + 4)[0]
            base = address - text
            if base < 0 or base % 0x1000:
                continue
            found = _tables_holding(image, base, base + record)
            if found:
                return found
    sys.exit('no menu string tables found')


def _tables_holding(image, base, record_address):
    def entry(offset):
        return struct.unpack_from('<I', image, offset)[0]

    def table(at, count):
        """The texts of the table at `at`, or None when it is not one."""
        if at < 0 or at + 4 * count > len(image):
            return None
        texts = []
        for i in range(count):
            record = entry(at + 4 * i) - base
            if not 0 <= record < len(image) - 8:
                return None
            tag, text = struct.unpack_from('<II', image, record)
            if not 0x100 < tag < 0x10000 or not 0 <= text - base < len(image):
                return None
            texts.append(utf16(image, text - base))
        return texts

    for slot in find_all(image, struct.pack('<I', record_address)):
        start = slot
        while entry(start - 4):
            start -= 4
        end = slot
        while entry(end):
            end += 4
        count = (end - start) // 4
        if count < 100:
            continue
        # The languages' tables follow one another, a zero between them.
        step = 4 * (count + 1)
        first = start
        while entry(first - 4) == 0 and table(first - step, count):
            first -= step
        result = []
        while texts := table(first + step * len(result), count):
            result.append(texts)
        return result
    return None


def main(args):
    if not args:
        sys.exit(__doc__)
    image = open(args[0], 'rb').read()
    languages = tables(image)
    english = next(t for t in languages if ENGLISH in t)
    own_name = english.index(ENGLISH)
    if len(args) == 1:
        for i, text in enumerate(english):
            print(f'{i}\t{text!r}')
        return
    if args[1] == '--index':
        indexes = [int(args[2])]
    else:
        wanted = args[1].lower()
        indexes = [i for i, t in enumerate(english) if t.lower() == wanted]
        if not indexes:
            sys.exit(f'no English entry is exactly {args[1]!r}')
    for i in indexes:
        print(f'[{i}] {english[i]!r}')
        for table in languages:
            print(f'  {table[own_name]}\t{table[i]!r}')


if __name__ == '__main__':
    main(sys.argv[1:])
