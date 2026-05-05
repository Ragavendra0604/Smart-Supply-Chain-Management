import axios from 'axios';
import { cacheManager } from '../utils/cache.js';

const WEATHER_CACHE_TTL = 15 * 60 * 1000; // 15 minutes

export const getWeatherFallback = () => ({
  condition: "Partly Cloudy",
  temperature: 20,
  humidity: 50,
  windSpeed: 10,
  fallback: true,
  note: "Using regional average (API Unavailable)"
});

export const getWeather = async (city) => {
  const cacheKey = `weather:${city.toLowerCase()}`;
  const cached = cacheManager.get(cacheKey);
  if (cached) return cached;

  try {
    const response = await axios.get(
      `https://api.openweathermap.org/data/2.5/weather`,
      {
        params: {
          q: city,
          appid: process.env.WEATHER_API_KEY,
          units: "metric"
        }
      }
    );

    const weatherData = {
      condition: response.data.weather[0].main,
      temperature: response.data.main.temp,
      humidity: response.data.main.humidity,
      windSpeed: response.data.wind.speed
    };

    cacheManager.set(cacheKey, weatherData, WEATHER_CACHE_TTL);
    return weatherData;

  } catch (error) {
    console.error("Weather API Error:", error.message);

    return getWeatherFallback();
  }
};


export default { getWeather, getWeatherFallback };
