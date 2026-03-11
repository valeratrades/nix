#!/home/v/nix/home/scripts/nix-run-cached

fn main() {
    for i in 0..10 {
        println!("{}", z_to_z_square(i));
    }
}

fn z_to_z_square(mut n: i32) -> String {
    let mut i = 0;
    while i < n {
        n -= i + 1;
        i += 1;
    }
    // at this point `i` is the group number

    let (x, y) = (i - n, n); // position within the group
    format!("({x}, {y})")
}
