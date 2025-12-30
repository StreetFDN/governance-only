'use client';

import { useRef, useEffect } from 'react';
import { motion, useSpring, useMotionValue, useAnimationFrame } from 'framer-motion';

// The spring now just smooths the raw position data slightly
const SPRING_CONFIG = { stiffness: 500, damping: 30 };

// The invisible box limits
const BOX_LIMITS = { x: 200, y: 60 };

const PhysicsLetter = ({ letter, mouseX, mouseY }: { letter: string, mouseX: any, mouseY: any }) => {
  const ref = useRef<HTMLDivElement>(null);

  // --- PHYSICS STATE ---
  const position = useRef({ x: 0, y: 0 });
  const velocity = useRef({ x: 0, y: 0 });
  const lastInteraction = useRef(Date.now());
  const isHovered = useRef(false);

  const x = useSpring(0, SPRING_CONFIG);
  const y = useSpring(0, SPRING_CONFIG);
  const rotate = useSpring(0, SPRING_CONFIG);

  // --- ANIMATION LOOP ---
  useAnimationFrame(() => {
    if (!ref.current) return;

    const rect = ref.current.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const mX = mouseX.get();
    const mY = mouseY.get();

    const dx = mX - centerX;
    const dy = mY - centerY;
    const distance = Math.sqrt(dx * dx + dy * dy);
    const radius = 200;

    // --- 1. APPLY FORCES ---
    if (distance < radius && mX > -100) { 
      isHovered.current = true;
      lastInteraction.current = Date.now();

      // Force magnitude
      const forceMagnitude = (1 - distance / radius) * 0.8; 
      const forceX = -(dx / distance) * forceMagnitude;
      const forceY = -(dy / distance) * forceMagnitude;

      // Apply force to velocity
      velocity.current.x += forceX;
      velocity.current.y += forceY;
    } else {
      isHovered.current = false;
    }

    // --- 2. REASSEMBLY FORCE ---
    const timeSinceInteraction = Date.now() - lastInteraction.current;
    if (timeSinceInteraction > 5000) {
      const homingForce = 0.02;
      velocity.current.x -= position.current.x * homingForce;
      velocity.current.y -= position.current.y * homingForce;
      
      velocity.current.x *= 0.9;
      velocity.current.y *= 0.9;
    }

    // --- 3. APPLY DAMPING (FRICTION) ---
    const damping = 0.98;
    velocity.current.x *= damping;
    velocity.current.y *= damping;

    // --- 4. UPDATE POSITION ---
    position.current.x += velocity.current.x;
    position.current.y += velocity.current.y;

    // --- 5. BOUNDARY COLLISION (BOUNCE) ---
    const bounceFactor = 0.8; 

    if (position.current.x > BOX_LIMITS.x) {
      position.current.x = BOX_LIMITS.x;
      velocity.current.x = -velocity.current.x * bounceFactor;
    } else if (position.current.x < -BOX_LIMITS.x) {
      position.current.x = -BOX_LIMITS.x;
      velocity.current.x = -velocity.current.x * bounceFactor;
    }

    if (position.current.y > BOX_LIMITS.y) {
      position.current.y = BOX_LIMITS.y;
      velocity.current.y = -velocity.current.y * bounceFactor;
    } else if (position.current.y < -BOX_LIMITS.y) {
      position.current.y = -BOX_LIMITS.y;
      velocity.current.y = -velocity.current.y * bounceFactor;
    }

    // --- 6. UPDATE MOTION VALUES ---
    x.set(position.current.x);
    y.set(position.current.y);
    rotate.set(velocity.current.x * 2);
  });

  return (
    <motion.div
      ref={ref}
      style={{ x, y, rotate }}
      className="inline-block cursor-default select-none text-4xl md:text-6xl font-serif font-medium text-gray-300 data-[theme=dark]:text-gray-600 transition-colors duration-300 leading-none will-change-transform"
    >
      {letter === " " ? "\u00A0" : letter}
    </motion.div>
  );
};

export default function PhysicsFooter() {
  const containerRef = useRef<HTMLDivElement>(null);
  const mouseX = useMotionValue(-1000);
  const mouseY = useMotionValue(-1000);

  const handleMouseMove = (e: React.MouseEvent) => {
    mouseX.set(e.clientX);
    mouseY.set(e.clientY);
  };

  const handleMouseLeave = () => {
    mouseX.set(-1000);
    mouseY.set(-1000);
  };

  const text = "ERC-S is powered by Street Labs";

  return (
    <div 
      ref={containerRef}
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
      // UPDATED: Removed background color and top border so it blends perfectly with the parent footer
      className="w-full overflow-hidden py-8 flex justify-center items-center"
    >
      <div className="flex flex-wrap justify-center gap-[0.1em] md:gap-[0.15em] px-4">
        {Array.from(text).map((char, i) => (
           <PhysicsLetter key={i} letter={char} mouseX={mouseX} mouseY={mouseY} />
        ))}
      </div>
    </div>
  );
}