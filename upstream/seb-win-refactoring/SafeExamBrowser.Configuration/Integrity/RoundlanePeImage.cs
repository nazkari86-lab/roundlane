// Roundlane additions, licensed under MPL-2.0. PE layout follows Microsoft PE specification.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;

namespace SafeExamBrowser.Configuration.Integrity
{
    internal sealed class RoundlanePeImage
    {
        internal sealed class Section
        {
            internal uint Rva, Size, RawOffset, RawSize, Flags;
            internal byte[] Expected;
        }
        internal readonly List<Section> Code = new List<Section>();
        internal sealed class LoaderOverride
        {
            internal uint BranchRva;
            internal byte[] Original, Stub;
        }
        internal readonly List<LoaderOverride> Overrides = new List<LoaderOverride>();
        private readonly List<Section> sections = new List<Section>();
        private readonly byte[] file;
        private readonly int directory;
        private readonly uint directoryCount;
        internal readonly ulong PreferredBase;
        internal readonly uint ImageSize;
        private readonly uint iatStart;
        private readonly ulong iatEnd;

        internal RoundlanePeImage(byte[] file, ulong loadedBase)
        {
            this.file = file;
            if (U16(0) != 0x5a4d) throw new InvalidDataException("Missing PE DOS header");
            var pe = checked((int)U32(0x3c));
            if (U32(pe) != 0x4550) throw new InvalidDataException("Missing PE signature");
            var machine = U16(pe + 4);
            if (machine != 0x14c && machine != 0x8664) throw new InvalidDataException("Unsupported owned PE machine");
            var number = U16(pe + 6);
            var optionalSize = U16(pe + 20);
            var optional = pe + 24;
            var magic = U16(optional);
            if (magic != 0x10b && magic != 0x20b) throw new InvalidDataException("Unsupported optional header");
            PreferredBase = magic == 0x20b ? U64(optional + 24) : U32(optional + 28);
            ImageSize = U32(optional + 56);
            if (ImageSize == 0 || ImageSize > 1024 * 1024 * 1024) throw new InvalidDataException("Invalid image size");
            directory = optional + (magic == 0x20b ? 112 : 96);
            directoryCount = U32(directory - 4);
            if (directoryCount > 16 || directory + directoryCount * 8 > optional + optionalSize) throw new InvalidDataException("Invalid PE directories");
            var table = optional + optionalSize;
            if (number == 0 || number > 96) throw new InvalidDataException("Invalid section count");
            for (var i = 0; i < number; i++)
            {
                var header = checked(table + i * 40);
                var size = U32(header + 8);
                var raw = U32(header + 16);
                var section = new Section { Rva = U32(header + 12), Size = size == 0 ? raw : size, RawSize = raw, RawOffset = U32(header + 20), Flags = U32(header + 36) };
                if (section.Size > 512 * 1024 * 1024 || (ulong)section.Rva + section.Size > ImageSize || (ulong)section.RawOffset + raw > (ulong)file.Length) throw new InvalidDataException("Section out of bounds");
                if (sections.Any(s => section.Rva < (ulong)s.Rva + s.Size && s.Rva < (ulong)section.Rva + section.Size)) throw new InvalidDataException("Overlapping PE sections");
                sections.Add(section);
                if ((section.Flags & 0x20000000) != 0 && (section.Flags & 0x02000000) == 0)
                {
                    section.Expected = new byte[section.Size];
                    Buffer.BlockCopy(file, checked((int)section.RawOffset), section.Expected, 0, checked((int)Math.Min(raw, section.Size)));
                    Code.Add(section);
                }
            }
            if (Code.Count == 0) throw new InvalidDataException("Owned module has no executable PE sections");
            iatStart = DirectoryRva(12);
            iatEnd = (ulong)iatStart + DirectorySize(12);
            if (iatEnd > ImageSize) throw new InvalidDataException("IAT outside image");
            ApplyRelocations(unchecked(loadedBase - PreferredBase));
            // Narrow compatibility for the authenticated Microsoft D3D build
            // observed in WPF. Unknown DVRT layouts stay byte-for-byte checked.
            // BDD feature numbers are NOT interpreted as instruction encodings.
            using (var hash = SHA256.Create())
            {
                if (BitConverter.ToString(hash.ComputeHash(file)).Replace("-", "").ToLowerInvariant() == "a05f99734f7c4822fefc12b367af21fd0976ed6608752fb1e1e80b6ece7ecbbb")
                {
                    Overrides.Add(new LoaderOverride { BranchRva = 0x363010, Original = file.Skip(FileOffset(0x363010, 5)).Take(5).ToArray(), Stub = new byte[] { 0xc3 } });
                    Overrides.Add(new LoaderOverride { BranchRva = 0x363020, Original = file.Skip(FileOffset(0x363020, 5)).Take(5).ToArray(), Stub = new byte[] { 0x48, 0xff, 0xe0 } });
                }
            }
        }

        internal bool IsLoaderMutable(uint rva)
        {
            // The loader replaces IAT entries. Do not mask arbitrary patches or .NET code.
            if (rva >= iatStart && (ulong)rva < iatEnd) return true;
            foreach (var patch in Overrides)
                if (rva > patch.BranchRva && rva <= patch.BranchRva + 4) return true;
            return false;
        }

        private void ApplyRelocations(ulong delta)
        {
            if (delta == 0) return;
            var start = DirectoryRva(5);
            var length = DirectorySize(5);
            // Position-independent images, including x64 CLR assemblies, can have
            // no fixups. Their expected code remains byte-for-byte unchanged.
            if (start == 0 && length == 0) return;
            if (start == 0 || length == 0) throw new InvalidDataException("Invalid relocation directory");
            var position = start;
            var end = checked(start + length);
            while (position < end)
            {
                var offset = FileOffset(position, 8);
                var page = U32(offset);
                var size = U32(offset + 4);
                if (size < 8 || size % 2 != 0 || (ulong)position + size > end) throw new InvalidDataException("Invalid relocation block");
                for (uint entry = 8; entry < size; entry += 2)
                {
                    var raw = U16(FileOffset(checked(position + entry), 2));
                    var kind = raw >> 12;
                    if (kind == 0) continue;
                    var rva = checked(page + (uint)(raw & 0xfff));
                    var section = Code.FirstOrDefault(s => rva >= s.Rva && (ulong)rva < (ulong)s.Rva + s.Size);
                    if (section == null) continue;
                    var index = checked((int)(rva - section.Rva));
                    var width = kind == 3 ? 4 : kind == 10 ? 8 : 0;
                    if (width == 0 || index + width > section.Expected.Length) throw new InvalidDataException("Unsupported code relocation");
                    var value = width == 8 ? unchecked(BitConverter.ToUInt64(section.Expected, index) + delta) : unchecked((uint)(BitConverter.ToUInt32(section.Expected, index) + delta));
                    var bytes = width == 8 ? BitConverter.GetBytes(value) : BitConverter.GetBytes((uint)value);
                    Buffer.BlockCopy(bytes, 0, section.Expected, index, width);
                }
                position = checked(position + size);
            }
        }

        private uint DirectoryRva(int index) => index < directoryCount ? U32(directory + index * 8) : 0;
        private uint DirectorySize(int index) => index < directoryCount ? U32(directory + index * 8 + 4) : 0;
        private int FileOffset(uint rva, uint length)
        {
            var section = sections.FirstOrDefault(s => rva >= s.Rva && (ulong)rva + length <= (ulong)s.Rva + s.RawSize);
            if (section == null) throw new InvalidDataException("PE directory out of file bounds");
            return checked((int)(section.RawOffset + rva - section.Rva));
        }
        private void Bounds(int offset, int size) { if (offset < 0 || offset > file.Length - size) throw new InvalidDataException("Truncated PE file"); }
        private ushort U16(int offset) { Bounds(offset, 2); return BitConverter.ToUInt16(file, offset); }
        private uint U32(int offset) { Bounds(offset, 4); return BitConverter.ToUInt32(file, offset); }
        private ulong U64(int offset) { Bounds(offset, 8); return BitConverter.ToUInt64(file, offset); }
    }
}
