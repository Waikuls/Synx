# AGENTS.md

กฎการทำงานสำหรับ agent ในโปรเจกต์นี้

## เป้าหมาย
- รักษาโครงสร้างโปรเจกต์ให้ชัดเจน
- รักษาหน้าตาและพฤติกรรมของ UI ให้ตรงกับ Fatality แบบเดิม
- แยก UI ออกจาก logic ของฟีเจอร์เมื่อฟีเจอร์เริ่มซับซ้อน

## โครงสร้างไฟล์
- `Fatality/main.lua` คือไฟล์หลักสำหรับเพิ่มหรือแก้เมนู, section, toggle, slider, dropdown, button, keybind, color picker และการประกอบ UI
- `src/source.luau` คือ core UI library ของ Fatality
- `examples/*.luau` คือไฟล์ตัวอย่างการใช้งาน
- ถ้าจะเพิ่มฟีเจอร์ใหม่ที่มี logic จริง ควรแยกไฟล์ใหม่ตามหน้าที่ของฟีเจอร์นั้น

## กฎการแก้เมนูและ UI
- ถ้าจะเพิ่มเมนูใหม่หรือแก้ของที่อยู่ในเมนู ให้แก้ใน `Fatality/main.lua`
- ต้องใช้รูปแบบ UI เดิมที่ library รองรับอยู่แล้ว เช่น `AddToggle`, `AddSlider`, `AddDropdown`, `AddButton`, `AddKeybind`, `AddColorPicker`
- ต้องคง layout แบบเดิมของระบบ เช่น menu, section, การวาง `left` `center` `right`
- ต้องคงรูปแบบการใช้งาน option ด้านขวาตามแพตเทิร์นเดิมด้วย `Option = true`
- ต้องคงชื่อและรูปแบบการตั้งชื่อให้ใกล้เคียงของเดิม อ่านง่าย และไม่หลุดธีม
- ห้ามสร้างคอมโพเนนต์ UI ใหม่แบบมั่ว ๆ ถ้า library เดิมมี element รองรับอยู่แล้ว

## กฎเรื่องหน้าตา
- เวลาปรับหรือเพิ่ม UI ต้องยึดตามหน้าตาเดิมของ Fatality จากโค้ดที่มีอยู่และผลลัพธ์จริงของ UI
- ห้ามเปลี่ยน theme, font, spacing, accent color, layout, animation หรือสไตล์รวมของ UI ถ้าไม่ได้ถูกสั่งโดยตรง
- ถ้าจะเพิ่ม element ใหม่ ต้องทำให้ดูกลมกลืนกับเมนูเดิม เช่น checkbox, dropdown, slider, ปุ่ม option, keybind

## กฎการเขียนฟีเจอร์
- ถ้าฟีเจอร์เล็กและ callback สั้น สามารถเขียนตรงใน `Fatality/main.lua` ได้
- ถ้าฟีเจอร์มี logic ยาว, state, loop, drawing, player tracking, cleanup, หรือ settings หลายตัว ให้แยกไฟล์ออกจาก `main.lua`
- ตัวอย่างฟีเจอร์ที่ควรแยกไฟล์: `ESP`, `Aimbot`, `Bullet Tracer`, `Thirdperson`, `Glow`, ระบบ config ที่ซับซ้อน
- `Fatality/main.lua` ควรเป็นตัวประกอบ UI และเรียกใช้ฟังก์ชันจากไฟล์ฟีเจอร์ ไม่ควรยัด logic ใหญ่ทั้งหมดไว้ไฟล์เดียว

## กฎการแก้ core library
- แก้ `src/source.luau` เฉพาะเมื่อจำเป็นต้องเปลี่ยนระดับ library
- ใช้ `src/source.luau` สำหรับการแก้ theme, style, layout engine, animation, behavior ของ component, หรือระบบภายในของ UI library
- ถ้าแค่เพิ่มเมนูหรือเพิ่มฟีเจอร์ ห้ามย้ายไปแก้ `src/source.luau` โดยไม่จำเป็น

## แนวทางเวลารับงานใหม่
- ถ้าผู้ใช้ขอเพิ่มเมนู, ปุ่ม, dropdown, slider, toggle หรือ section: ให้เริ่มแก้ที่ `Fatality/main.lua`
- ถ้าผู้ใช้ขอให้ฟีเจอร์ใช้งานได้จริง: เพิ่ม UI ใน `Fatality/main.lua` แล้วแยก logic ตามความเหมาะสม
- ถ้าผู้ใช้ขอเปลี่ยนหน้าตา UI ทั้งระบบ: ค่อยไปแก้ `src/source.luau`
- ต้องพยายามรักษาความสอดคล้องของ naming, spacing, grouping และพฤติกรรมของเมนูให้เหมือนของเดิม

## สิ่งที่ควรหลีกเลี่ยง
- อย่าทำให้ `Fatality/main.lua` กลายเป็นไฟล์รวม logic ทุกอย่างโดยไม่จำเป็น
- อย่าเปลี่ยนโครงสร้างหรือหน้าตา UI จนหลุดจากสไตล์ Fatality เดิม
- อย่าเพิ่มตัวอย่างหรือไฟล์ใหม่ซ้ำซ้อน ถ้ายังใช้โครงสร้างเดิมให้ชัดเจนได้
- อย่าแก้ `src/source.luau` เพื่อทำเรื่องที่ควรอยู่ใน `main.lua` หรือไฟล์ฟีเจอร์
