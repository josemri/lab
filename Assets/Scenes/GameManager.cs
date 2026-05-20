using UnityEngine;
using UnityEngine.SceneManagement;
using TMPro;
public class GameManager : MonoBehaviour
{
    public int lives = 10;
    public TMP_Text livesText;

    public void DamagePlayer()
    {
        lives--;
        livesText.text = "Lives: " + lives;
        if (lives <= 0)
        {
            Debug.Log("GAME OVER");
            SceneManager.LoadScene("Game Over");
        }
    }
}