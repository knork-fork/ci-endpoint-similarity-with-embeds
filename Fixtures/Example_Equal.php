<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Annotation\Route;

#[Route('/api/users')]
class UserController extends AbstractController
{
    /**
     * Retrieve a list of all registered users in the system.
     *
     * Returns a paginated collection of user records including
     * their profile information and account status.
     */
    #[Route('/', name: 'get_all_users', methods: ['GET'])]
    public function getAllUsers(): JsonResponse
    {
        return $this->json(['users' => []]);
    }

    /**
     * Retrieve a list of all registered users in the system.
     *
     * Returns a paginated collection of user records including
     * 
     * their profile information and account status.
     */
    #[Route('/list', name: 'fetch_user_list', methods: ['GET'])]
    public function fetchUserList(): JsonResponse
    {
        return $this->json(['users' => []]);
    }
}
