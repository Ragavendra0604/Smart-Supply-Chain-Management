import axios from 'axios';

export const getWeather = async (city) => {
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

    return {
      condition: response.data.weather[0].main,
      temperature: response.data.main.temp,
      humidity: response.data.main.humidity,
      windSpeed: response.data.wind.speed
    };

  } catch (error) {
    console.error("Weather API Error:", error.message);

    return {
      condition: "Clear",
      temperature: 30,
      humidity: 50,
      windSpeed: 5,
      fallback: true
    };
  }
};


export default { getWeather };
