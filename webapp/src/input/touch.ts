import { useEffect, useState } from 'react';

export function needsTouchControls(
  width: number,
  height: number,
  userAgent: string,
  platform = '',
  touchPoints = 0,
): boolean {
  const mobile =
    /Android|iPhone|iPad|iPod|IEMobile|Opera Mini/i.test(userAgent) || (platform === 'MacIntel' && touchPoints > 1);
  return mobile || (width <= 600 && height >= width);
}

export function useTouchControls(): boolean {
  const detect = () =>
    needsTouchControls(
      window.innerWidth,
      window.innerHeight,
      navigator.userAgent,
      navigator.platform,
      navigator.maxTouchPoints,
    );
  const [touch, setTouch] = useState(detect);
  useEffect(() => {
    const update = () => setTouch(detect());
    window.addEventListener('resize', update);
    window.addEventListener('orientationchange', update);
    return () => {
      window.removeEventListener('resize', update);
      window.removeEventListener('orientationchange', update);
    };
  }, []);
  return touch;
}
