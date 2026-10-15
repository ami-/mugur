package main

import "core:fmt"
import "core:os"
import "editor"
import "tui"

VERSION :: #config(VERSION, "dev")

main :: proc() {
	if len(os.args) > 1 && (os.args[1] == "-v" || os.args[1] == "--version") {
		fmt.println(VERSION)
		return
	}

	ed := editor.make_editor()
	defer editor.destroy_editor(&ed)
	editor.load_text(&ed.buf, FILE)

	tui.run(&ed)

	_ = editor.write_to(&ed.buf, os.to_writer(os.stdout))
}


FILE :: `1. Line one
2. Line two
3. Line three
4. Line four
5. Line five
6. Line six
7. Line seven
8. Line eight
9. Line nine
10. Line ten
11. Line eleven
12. Line twelve
13. Line thirteen
14. Line fourteen
15. Line fifteen
16. Line sixteen
17. Line seventeen
18. Line eighteen
19. Line nineteen
20. Line twenty
21. Line twenty-one
22. Line twenty-two
23. Line twenty-three
24. Line twenty-four
25. Line twenty-five
26. Line twenty-six
27. Line twenty-seven
28. Line twenty-eight
29. Line twenty-nine
30. Line thirty
31. Line thirty-one
32. Line thirty-two
33. Line thirty-three
34. Line thirty-four
35. Line thirty-five
36. Line thirty-six
37. Line thirty-seven
38. Line thirty-eight
39. Line thirty-nine
40. Line forty
41. Line forty-one
42. Line forty-two
43. Line forty-three
44. Line forty-four
45. Line forty-five
46. Line forty-six
47. Line forty-seven
48. Line forty-eight
49. Line forty-nine
50. Line fifty`
