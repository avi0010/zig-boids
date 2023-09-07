const std = @import("std");
const RndGen = std.rand.DefaultPrng;

pub const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const width: u32 = 1920;
const height: u32 = 1080;
const num_boids: u32 = 1000;
const perception: f32 = 100;

const colors = [_]c.struct_Color{
    c.LIGHTGRAY,
    c.GRAY,
    c.DARKGRAY,
    c.YELLOW,
    c.GOLD,
    c.ORANGE,
    c.PINK,
    c.RED,
    c.GREEN,
    c.LIME,
    c.SKYBLUE,
    c.BLUE,
    c.DARKBLUE,
    c.PURPLE,
    c.BEIGE,
    c.WHITE,
    c.MAGENTA,
    c.RAYWHITE,
};

const boid = struct {
    position: c.struct_Vector2,
    velocity: c.struct_Vector2,
    color: c.struct_Color = c.SKYBLUE,

    const Self = @This();

    fn init(rnd: *std.rand.Xoshiro256) Self {
        const pos_x = rnd.random().floatExp(f32) * width;
        const pos_y = rnd.random().floatExp(f32) * height;
        const vel_x: f32 = @floatFromInt(rnd.random().intRangeAtMost(i32, -5, 5));
        const vel_y: f32 = @floatFromInt(rnd.random().intRangeAtMost(i32, -5, 5));
        const rand = rnd.random().intRangeAtMost(u32, 0, colors.len - 1);
        const color = colors[rand];
        return Self{
            .position = c.struct_Vector2{ .x = pos_x, .y = pos_y },
            .velocity = c.struct_Vector2{ .x = vel_x, .y = vel_y },
            .color = color,
        };
    }

    fn update(self: *Self) void {
        if (self.position.x > width) {
            self.position.x = 0;
        }
        if (self.position.x < 0) {
            self.position.x = width;
        }
        if (self.position.y > height) {
            self.position.y = 0;
        }
        if (self.position.y < 0) {
            self.position.y = height;
        }

        self.velocity = c.Vector2Normalize(self.velocity);
        self.position = c.Vector2Add(self.position, c.Vector2Scale(self.velocity, 4));
    }

    fn draw(self: Self) void {
        var color = c.SKYBLUE;
        _ = color;
        const norm_dir = c.struct_Vector2{ .x = self.velocity.y * -1, .y = self.velocity.x };
        const bottom = c.Vector2Subtract(self.position, c.Vector2Scale(self.velocity, 5));
        c.DrawTriangle(
            c.Vector2Add(self.position, c.Vector2Scale(self.velocity, 5)),
            c.Vector2Subtract(bottom, c.Vector2Scale(norm_dir, 5)),
            c.Vector2Add(bottom, c.Vector2Scale(norm_dir, 5)),
            self.color,
        );
    }
};

const state = struct {
    boids: [num_boids]boid,
    const Self = @This();

    fn init() Self {
        var boids: [num_boids]boid = undefined;
        const seed = @as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
        var rnd = RndGen.init(seed);
        for (0..num_boids) |i| {
            var b = boid.init(&rnd);
            boids[i] = b;
        }
        return Self{ .boids = boids };
    }

    fn checkCollision(b: boid) u8 {
        const range = perception / 2;
        if (b.position.x < range and b.velocity.x < -0.01) {
            return 1;
        }
        if (b.position.x > width - range and b.velocity.x > 0.01) {
            return 3;
        }
        if (b.position.y < range and b.velocity.y < -0.01) {
            return 2;
        }
        if (b.position.y > height - range and b.velocity.y > 0.01) {
            return 4;
        }
        return 0;
    }

    fn update(self: *Self) void {
        for (0..num_boids) |i| {
            // Separation
            var separationDirection = c.Vector2Zero();

            // Alignment
            var averageAlignment = c.Vector2Zero();

            // Cohesion
            var cohesionDirection = c.Vector2Zero();
            var localCenterOfMass = c.Vector2Zero();
            var numLocalBoids: u32 = 0;
            for (0..num_boids) |j| {
                if (i == j) {
                    continue;
                }
                if (c.Vector2Distance(self.boids[i].position, self.boids[j].position) > perception) {
                    continue;
                }

                numLocalBoids += 1;

                // Separation
                const difference = c.Vector2Subtract(self.boids[i].position, self.boids[j].position);
                separationDirection = c.Vector2Add(
                    separationDirection,
                    c.Vector2Scale(c.Vector2Normalize(difference), 1 + ((perception / 4) / c.Vector2LengthSqr(difference))),
                );

                // Alignment
                averageAlignment = c.Vector2Add(averageAlignment, self.boids[j].velocity);

                // Cohesion
                localCenterOfMass = c.Vector2Add(localCenterOfMass, self.boids[j].position);
            }

            // TODO: Avoid window edges instead of wrapping
            const col = checkCollision(self.boids[i]);
            if (col != 0) {
                const steering_dir = switch (col) {
                    1 => c.Vector2{ .x = self.boids[i].velocity.x * -1, .y = self.boids[i].velocity.y },
                    2 => c.Vector2{ .x = self.boids[i].velocity.x, .y = self.boids[i].velocity.y * -1 },
                    3 => c.Vector2{ .x = self.boids[i].velocity.x * -1, .y = self.boids[i].velocity.y },
                    4 => c.Vector2{ .x = self.boids[i].velocity.x, .y = self.boids[i].velocity.y * -1 },
                    else => unreachable,
                };
                const dir = c.Vector2Normalize(c.Vector2Lerp(self.boids[i].velocity, steering_dir, 1.1));
                self.boids[i].velocity = c.Vector2Add(self.boids[i].velocity, c.Vector2Scale(dir, 0.1));
            }
            if (numLocalBoids > 0) {
                const one = @as(f32, 1);
                const refactor: f32 = @floatFromInt(numLocalBoids);
                const invert = one / refactor;

                // Separation
                if (c.Vector2LengthSqr(separationDirection) != 0) {
                    separationDirection = c.Vector2Scale(separationDirection, invert);
                    const temp = c.Vector2Normalize(c.Vector2Lerp(self.boids[i].velocity, separationDirection, 0.2));
                    self.boids[i].velocity = c.Vector2Add(self.boids[i].velocity, temp);
                }

                //alignment
                if (c.Vector2LengthSqr(separationDirection) != 0) {
                    averageAlignment = c.Vector2Scale(averageAlignment, invert);
                    const temp = c.Vector2Normalize(c.Vector2Lerp(self.boids[i].velocity, c.Vector2Normalize(averageAlignment), 0.4));
                    self.boids[i].velocity = c.Vector2Add(self.boids[i].velocity, temp);
                }

                //Cohesion
                if (c.Vector2LengthSqr(localCenterOfMass) != 0) {
                    localCenterOfMass = c.Vector2Scale(localCenterOfMass, invert);
                    cohesionDirection = c.Vector2Subtract(localCenterOfMass, self.boids[i].position);
                    const temp = c.Vector2Normalize(c.Vector2Lerp(self.boids[i].velocity, c.Vector2Normalize(cohesionDirection), 0.4));
                    self.boids[i].velocity = c.Vector2Add(self.boids[i].velocity, temp);
                }
            }
        }
    }

    fn render(self: *Self) void {
        self.update();
        for (0..num_boids) |i| {
            self.boids[i].update();
            self.boids[i].draw();
        }
    }
};

pub fn main() void {
    c.InitWindow(width, height, "Boid Simulation");
    c.ToggleFullscreen();
    c.SetTargetFPS(120);
    var g = state.init();

    while (!c.WindowShouldClose()) {
        c.BeginDrawing();
        c.ClearBackground(c.BLACK);
        g.render();
        // c.DrawFPS(10, 10);
        c.EndDrawing();
    }
    c.CloseWindow(); // Close window and OpenGL context
}
